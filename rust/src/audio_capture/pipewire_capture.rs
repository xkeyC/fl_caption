use super::traits::{AudioCapture, AudioCaptureConfig, AudioCaptureInfo};
use anyhow::Result;
use pipewire as pw;
use pw::{properties::properties, spa};
use spa::param::format::{MediaSubtype, MediaType};
use spa::param::format_utils;
use spa::pod::Pod;
use std::convert::TryInto;
use std::mem;
use std::sync::mpsc;
use std::thread;
use tokio_util::sync::CancellationToken;

struct UserData {
    format: spa::param::audio::AudioInfoRaw,
    tx: mpsc::Sender<Vec<f32>>,
    target_sample_rate: u32,
    cancel_token: CancellationToken,
}

pub struct PipewireAudioCapture {
    config: AudioCaptureConfig,
}

impl AudioCapture for PipewireAudioCapture {
    fn new(config: AudioCaptureConfig) -> Result<Self> {
        // Initialize PipeWire
        pw::init();
        
        Ok(Self { config })
    }

    fn get_info(&self) -> AudioCaptureInfo {
        AudioCaptureInfo {
            device_name: self.config.device.clone().unwrap_or_else(|| "Default PipeWire Device".to_string()),
            sample_rate: self.config.target_sample_rate,
            channels: self.config.target_channels,
        }
    }

    fn start_capture(&self, cancel_token: CancellationToken) -> Result<mpsc::Receiver<Vec<f32>>> {
        let (tx, rx) = mpsc::channel::<Vec<f32>>();
        
        let config = self.config.clone();
        let cancel_token_clone = cancel_token.clone();
        
        thread::spawn(move || {
            if let Err(e) = run_pipewire_capture(config, tx, cancel_token_clone) {
                eprintln!("PipeWire capture error: {}", e);
            }
        });

        Ok(rx)
    }
}

fn run_pipewire_capture(
    config: AudioCaptureConfig,
    tx: mpsc::Sender<Vec<f32>>,
    cancel_token: CancellationToken,
) -> Result<()> {
    println!("PipeWire: initializing capture with config: {:?}", config);
    
    let mainloop = pw::main_loop::MainLoop::new(None)?;
    println!("PipeWire: mainloop created");
    
    let context = pw::context::Context::new(&mainloop)?;
    println!("PipeWire: context created");
    
    let core = context.connect(None)?;
    println!("PipeWire: core connected");

    let user_data = UserData {
        format: Default::default(),
        tx,
        target_sample_rate: config.target_sample_rate,
        cancel_token: cancel_token.clone(),
    };

    // Create properties for the stream
    let mut props = properties! {
        *pw::keys::MEDIA_TYPE => "Audio",
        *pw::keys::MEDIA_CATEGORY => "Capture",
        *pw::keys::MEDIA_ROLE => "Music",
    };

    // For capturing from speakers (output), we need to capture from sink monitor
    if !config.is_input {
        props.insert(*pw::keys::STREAM_CAPTURE_SINK, "true");
        println!("PipeWire: configured for sink monitor capture (speakers)");
    } else {
        println!("PipeWire: configured for microphone capture");
    }

    // Set target device if specified
    if let Some(ref device) = config.device {
        props.insert(*pw::keys::TARGET_OBJECT, device.clone());
        println!("PipeWire: target device set to: {}", device);
    }

    println!("PipeWire: creating stream with properties: {:?}", props);
    let stream = pw::stream::Stream::new(&core, "audio-capture", props)?;
    println!("PipeWire: stream created successfully");

    let _listener = stream
        .add_local_listener_with_user_data(user_data)
        .param_changed(|_, user_data, id, param| {
            if user_data.cancel_token.is_cancelled() {
                return;
            }

            println!("PipeWire: param_changed callback called with id: {:?}", id);

            let Some(param) = param else {
                println!("PipeWire: param is None, clearing format");
                return;
            };
            
            if id != pw::spa::param::ParamType::Format.as_raw() {
                println!("PipeWire: ignoring non-format param: {:?}", id);
                return;
            }

            let (media_type, media_subtype) = match format_utils::parse_format(param) {
                Ok(v) => {
                    println!("PipeWire: parsed format - media_type: {:?}, media_subtype: {:?}", v.0, v.1);
                    v
                },
                Err(e) => {
                    println!("PipeWire: failed to parse format: {:?}", e);
                    return;
                },
            };

            // Only accept raw audio
            if media_type != MediaType::Audio || media_subtype != MediaSubtype::Raw {
                println!("PipeWire: rejecting non-raw audio format");
                return;
            }

            if let Err(e) = user_data.format.parse(param) {
                eprintln!("Failed to parse audio format: {}", e);
                return;
            }

            println!(
                "PipeWire capturing rate:{} channels:{}",
                user_data.format.rate(),
                user_data.format.channels()
            );
        })
        .process(|stream, user_data| {
            if user_data.cancel_token.is_cancelled() {
                return;
            }

            match stream.dequeue_buffer() {
                None => {
                    println!("PipeWire: out of buffers");
                }
                Some(mut buffer) => {
                    let datas = buffer.datas_mut();
                    if datas.is_empty() {
                        println!("PipeWire: empty buffer data");
                        return;
                    }

                    let data = &mut datas[0];
                    let n_channels = user_data.format.channels();
                    let sample_rate = user_data.format.rate();
                    let n_samples = data.chunk().size() / (mem::size_of::<f32>() as u32);

                    // Only print debug info occasionally to avoid spam
                    use std::sync::atomic::{AtomicU32, Ordering};
                    static DEBUG_COUNTER: AtomicU32 = AtomicU32::new(0);
                    let counter = DEBUG_COUNTER.fetch_add(1, Ordering::Relaxed);
                    // if counter % 100 == 0 {  // Print every 100 buffers
                    //     println!("PipeWire: processing buffer #{} with {} samples, {} channels, {} Hz", 
                    //             counter, n_samples, n_channels, sample_rate);
                    // }

                    if let Some(samples) = data.data() {
                        // Only print this debug info occasionally
                        // if counter % 100 == 0 {
                        //     println!("PipeWire: raw buffer size: {} bytes", samples.len());
                        // }
                        
                        // Convert raw bytes to f32 samples
                        let mut audio_samples = Vec::with_capacity((n_samples / n_channels) as usize);
                        
                        for n in (0..n_samples).step_by(n_channels as usize) {
                            let mut channel_sum = 0.0f32;
                            let mut valid_channels = 0;
                            
                            // Mix all channels to mono
                            for c in 0..n_channels {
                                let sample_idx = (n + c) as usize;
                                if sample_idx < n_samples as usize {
                                    let start = sample_idx * mem::size_of::<f32>();
                                    let end = start + mem::size_of::<f32>();
                                    if end <= samples.len() {
                                        let sample_bytes = &samples[start..end];
                                        if let Ok(sample_array) = sample_bytes.try_into() {
                                            let sample = f32::from_le_bytes(sample_array);
                                            channel_sum += sample;
                                            valid_channels += 1;
                                        }
                                    }
                                }
                            }
                            
                            if valid_channels > 0 {
                                audio_samples.push(channel_sum / valid_channels as f32);
                            }
                        }

                        if counter % 100 == 0 {
                            println!("PipeWire: converted to {} mono samples", audio_samples.len());
                        }

                        // Resample if necessary
                        let resampled_samples = if sample_rate != user_data.target_sample_rate {
                            let resampled = resample_audio(&audio_samples, sample_rate, user_data.target_sample_rate);
                            if counter % 100 == 0 {
                                println!("PipeWire: resampled from {} Hz to {} Hz: {} -> {} samples", 
                                        sample_rate, user_data.target_sample_rate, audio_samples.len(), resampled.len());
                            }
                            resampled
                        } else {
                            audio_samples
                        };

                        if !resampled_samples.is_empty() {
                            if counter % 100 == 0 {
                                // println!("PipeWire: sending {} samples to channel", resampled_samples.len());
                            }
                            if let Err(e) = user_data.tx.send(resampled_samples) {
                                println!("PipeWire: failed to send samples: {}", e);
                            }
                        } else if counter % 100 == 0 {
                            println!("PipeWire: no samples to send");
                        }
                    } else {
                        println!("PipeWire: no sample data in buffer");
                    }
                }
            }
        })
        .register()?;

    // Set up audio format parameters - be more specific about what we want
    let mut audio_info = spa::param::audio::AudioInfoRaw::new();
    audio_info.set_format(spa::param::audio::AudioFormat::F32LE);
    // Set specific sample rate and channels to try to match what we need
    audio_info.set_rate(config.target_sample_rate);
    audio_info.set_channels(config.target_channels);
    
    println!("PipeWire: requesting format F32LE, rate {}, channels {}", 
             config.target_sample_rate, config.target_channels);
    
    let obj = pw::spa::pod::Object {
        type_: pw::spa::utils::SpaTypes::ObjectParamFormat.as_raw(),
        id: pw::spa::param::ParamType::EnumFormat.as_raw(),
        properties: audio_info.into(),
    };
    
    let values: Vec<u8> = pw::spa::pod::serialize::PodSerializer::serialize(
        std::io::Cursor::new(Vec::new()),
        &pw::spa::pod::Value::Object(obj),
    )?
    .0
    .into_inner();

    let mut params = [Pod::from_bytes(&values).ok_or_else(|| anyhow::anyhow!("Failed to create Pod from bytes"))?];
    println!("PipeWire: created audio format parameters");

    // Connect the stream
    println!("PipeWire: connecting stream...");
    stream.connect(
        spa::utils::Direction::Input,
        None,
        pw::stream::StreamFlags::AUTOCONNECT
            | pw::stream::StreamFlags::MAP_BUFFERS
            | pw::stream::StreamFlags::RT_PROCESS,
        &mut params,
    )?;
    println!("PipeWire: stream connected successfully");

    // Run the main loop properly
    println!("PipeWire: starting main loop...");
    
    // We need to handle the main loop differently
    // Let's try running it in a separate thread and use a channel to signal completion
    let (_main_tx, _main_rx) = std::sync::mpsc::channel::<()>();
    let cancel_clone = cancel_token.clone();
    
    std::thread::spawn(move || {
        // Monitor for cancellation and quit the mainloop
        while !cancel_clone.is_cancelled() {
            std::thread::sleep(std::time::Duration::from_millis(100));
        }
        println!("PipeWire: cancel detected, sending quit signal");
        // TODO: Need to find a way to signal the mainloop to quit
    });
    
    // Start the main loop in a blocking manner
    println!("PipeWire: calling mainloop.run() - this should start processing audio");
    
    // The mainloop.run() should block and process events
    // We'll need to find another way to exit it when cancelled
    mainloop.run();
    
    println!("PipeWire: mainloop.run() completed");

    println!("PipeWire audio capture stopped");
    Ok(())
}

/// Simple audio resampling using linear interpolation
fn resample_audio(input: &[f32], input_rate: u32, output_rate: u32) -> Vec<f32> {
    if input_rate == output_rate {
        return input.to_vec();
    }

    let ratio = output_rate as f64 / input_rate as f64;
    let output_len = (input.len() as f64 * ratio).ceil() as usize;
    let mut output = Vec::with_capacity(output_len);

    for i in 0..output_len {
        let src_index = i as f64 / ratio;
        let src_index_floor = src_index.floor() as usize;
        let src_index_ceil = (src_index_floor + 1).min(input.len() - 1);
        let fraction = src_index - src_index_floor as f64;

        if src_index_floor < input.len() {
            let sample = if src_index_ceil == src_index_floor {
                input[src_index_floor]
            } else {
                let sample1 = input[src_index_floor];
                let sample2 = input[src_index_ceil];
                sample1 + (sample2 - sample1) * fraction as f32
            };
            output.push(sample);
        }
    }

    output
}

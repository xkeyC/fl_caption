use super::traits::{AudioCapture, AudioCaptureConfig, AudioCaptureInfo};
use anyhow::Result;
use core_media_rs::cm_sample_buffer::CMSampleBuffer;
use screencapturekit::{
    shareable_content::SCShareableContent,
    stream::{
        configuration::SCStreamConfiguration, content_filter::SCContentFilter,
        output_trait::SCStreamOutputTrait, output_type::SCStreamOutputType, SCStream,
    },
};
use std::sync::mpsc;
use std::thread;
use std::time::Duration;
use tokio_util::sync::CancellationToken;


#[cfg (target_os = "macos" )]
#[link (name = "CoreMedia", kind = "framework" )]
extern "C" {}

#[cfg (target_os = "macos" )]
#[link (name = "ScreencaptureKit", kind = "framework" )]
extern "C" {}

pub struct MacosAudioCapture {
    config: AudioCaptureConfig,
}

struct AudioStreamOutput {
    sender: mpsc::Sender<CMSampleBuffer>,
}

impl SCStreamOutputTrait for AudioStreamOutput {
    fn did_output_sample_buffer(
        &self,
        sample_buffer: CMSampleBuffer,
        of_type: SCStreamOutputType,
    ) {
        // Only process audio samples
        if let SCStreamOutputType::Audio = of_type {
            if let Err(_) = self.sender.send(sample_buffer) {
                // Channel closed, ignore error
            }
        }
    }
}

impl AudioCapture for MacosAudioCapture {
    fn new(config: AudioCaptureConfig) -> Result<Self> {
        // Validate that we can access ScreenCaptureKit
        if let Err(_) = SCShareableContent::get() {
            anyhow::bail!("Failed to access ScreenCaptureKit - ensure app has screen recording permissions");
        }
        
        println!("ScreenCaptureKit audio capture initialized");
        
        Ok(Self { config })
    }

    fn get_info(&self) -> AudioCaptureInfo {
        AudioCaptureInfo {
            device_name: "macOS System Audio (ScreenCaptureKit)".to_string(),
            sample_rate: self.config.target_sample_rate,
            channels: self.config.target_channels,
        }
    }

    fn start_capture(&self, cancel_token: CancellationToken) -> Result<mpsc::Receiver<Vec<f32>>> {
        let (tx, rx) = mpsc::channel::<Vec<f32>>();
        
        let config = self.config.clone();
        let cancel_token_clone = cancel_token.clone();
        
        thread::spawn(move || {
            if let Err(e) = run_screencapturekit_capture(config, tx, cancel_token_clone) {
                eprintln!("ScreenCaptureKit capture error: {}", e);
            }
        });

        Ok(rx)
    }
}

fn run_screencapturekit_capture(
    config: AudioCaptureConfig,
    tx: mpsc::Sender<Vec<f32>>,
    cancel_token: CancellationToken,
) -> Result<()> {
    println!("ScreenCaptureKit: initializing system audio capture with config: {:?}", config);
    
    // Create a channel for receiving audio samples from ScreenCaptureKit
    let (sc_tx, sc_rx) = mpsc::channel::<CMSampleBuffer>();
    
    // Create stream configuration for audio capture
    let stream_config = SCStreamConfiguration::new()
        .set_captures_audio(true)
        .map_err(|e| anyhow::anyhow!("Failed to create stream configuration: {:?}", e))?;
    
    // Get the main display for the content filter
    let shareable_content = SCShareableContent::get()
        .map_err(|e| anyhow::anyhow!("Failed to get shareable content: {:?}", e))?;
    
    let displays = shareable_content.displays();
    if displays.is_empty() {
        anyhow::bail!("No displays found");
    }
    
    let display = &displays[0];
    println!("ScreenCaptureKit: using display for audio capture");
    
    // Create content filter - we only want audio, so exclude all windows
    let filter = SCContentFilter::new().with_display_excluding_windows(display, &[]);
    
    // Create the stream
    let mut stream = SCStream::new(&filter, &stream_config);
    
    // Add audio output handler
    stream.add_output_handler(
        AudioStreamOutput { sender: sc_tx },
        SCStreamOutputType::Audio,
    );
    
    // Start capture
    stream.start_capture()
        .map_err(|e| anyhow::anyhow!("Failed to start capture: {:?}", e))?;
    
    println!("ScreenCaptureKit: audio capture started");
    
    // Process audio samples in a loop
    let target_sample_rate = config.target_sample_rate;
    
    loop {
        if cancel_token.is_cancelled() {
            println!("ScreenCaptureKit: cancellation requested, stopping capture");
            break;
        }
        
        // Try to receive a sample buffer with timeout
        match sc_rx.recv_timeout(Duration::from_millis(100)) {
            Ok(sample_buffer) => {
                // Process the audio sample buffer
                if let Some(audio_samples) = process_sample_buffer(&sample_buffer, target_sample_rate) {
                    if let Err(_) = tx.send(audio_samples) {
                        // Channel closed, exit
                        break;
                    }
                }
            }
            Err(mpsc::RecvTimeoutError::Timeout) => {
                // No data received, continue loop
                continue;
            }
            Err(mpsc::RecvTimeoutError::Disconnected) => {
                // Sender disconnected, exit
                break;
            }
        }
    }
    
    // Stop capture
    if let Err(e) = stream.stop_capture() {
        eprintln!("Failed to stop capture: {:?}", e);
    }
    
    // Give some time for cleanup
    thread::sleep(Duration::from_millis(100));
    
    println!("ScreenCaptureKit: audio capture stopped");
    Ok(())
}

fn process_sample_buffer(sample_buffer: &CMSampleBuffer, target_sample_rate: u32) -> Option<Vec<f32>> {
    // Get the audio buffer list from the sample buffer
    let audio_buffer_list = sample_buffer.get_audio_buffer_list().ok()?;
    
    if audio_buffer_list.num_buffers() == 0 {
        return None;
    }
    
    // default sample rate for macOS audio capture
    // https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/samplerate
    let actual_sample_rate = 48000u32; // Common system audio sample rate on macOS
        
    let buffer = audio_buffer_list.get(0)?;
    let data = buffer.data();
    
    if data.is_empty() {
        return None;
    }
    
    let num_channels = buffer.number_channels as usize;
    let data_size = buffer.data_bytes_size as usize;
    
    // Detect audio format based on data size patterns
    // ScreenCaptureKit typically provides 32-bit float, but can also be 16-bit PCM
    let (bytes_per_sample, is_float) = if data_size % (num_channels * 4) == 0 {
        (4, true)  // 32-bit float
    } else if data_size % (num_channels * 2) == 0 {
        (2, false) // 16-bit PCM
    } else {
        println!("Unable to determine audio format from data size: {} bytes, {} channels", data_size, num_channels);
        return None;
    };
    
    let frames_count = data_size / (bytes_per_sample * num_channels);
    
    if frames_count == 0 {
        return None;
    }
    
    // println!("Processing audio: {} channels, {} bytes per sample, {} frames, actual rate: {}Hz, target rate: {}Hz", 
    //          num_channels, bytes_per_sample, frames_count, actual_sample_rate, target_sample_rate);
    
    // Convert to mono f32 samples - similar to extracting PCM data from CMBlockBuffer
    let mut mono_samples = Vec::with_capacity(frames_count);
    
    // Process frames (interleaved channel data)
    for frame in 0..frames_count {
        let mut channel_sum = 0.0f32;
        let mut valid_channels = 0;
        
        // Process each channel in the frame
        for channel in 0..num_channels {
            let sample_offset = (frame * num_channels + channel) * bytes_per_sample;
            
            if sample_offset + bytes_per_sample <= data_size {
                let sample_bytes = &data[sample_offset..sample_offset + bytes_per_sample];
                
                let sample_f32 = if is_float && bytes_per_sample == 4 {
                    // 32-bit float format (typical for ScreenCaptureKit)
                    if let Ok(sample_array) = <[u8; 4]>::try_from(sample_bytes) {
                        f32::from_le_bytes(sample_array)
                    } else {
                        continue;
                    }
                } else if !is_float && bytes_per_sample == 2 {
                    // 16-bit PCM format - convert to f32 normalized range (-1.0 to 1.0)
                    if let Ok(sample_array) = <[u8; 2]>::try_from(sample_bytes) {
                        let sample_i16 = i16::from_le_bytes(sample_array);
                        sample_i16 as f32 / 32768.0
                    } else {
                        continue;
                    }
                } else {
                    continue;
                };
                
                channel_sum += sample_f32;
                valid_channels += 1;
            }
        }
        
        // Convert multi-channel to mono by averaging, or keep mono as-is
        if valid_channels > 0 {
            let mono_sample = if num_channels == 1 {
                channel_sum
            } else {
                channel_sum / valid_channels as f32
            };
            mono_samples.push(mono_sample);
        }
    }
    
    if mono_samples.is_empty() {
        return None;
    }
    
    // Resample if needed
    let resampled_samples = if actual_sample_rate as u32 != target_sample_rate {
        resample_audio(&mono_samples, actual_sample_rate as u32, target_sample_rate)
    } else {
        mono_samples
    };
    
    Some(resampled_samples)
}

/// Simple audio resampling using linear interpolation
/// Similar to the implementation in cpal_capture.rs and pipewire_capture.rs
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
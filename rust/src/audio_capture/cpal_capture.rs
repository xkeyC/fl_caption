use super::traits::{AudioCapture, AudioCaptureConfig, AudioCaptureInfo};
use anyhow::Result;
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use std::sync::mpsc;
use std::thread;
use std::time::Duration;
use tokio_util::sync::CancellationToken;

pub struct CpalAudioCapture {
    config: AudioCaptureConfig,
    device_name: String,
    sample_rate: u32,
    channels: u32,
}

impl AudioCapture for CpalAudioCapture {
    fn new(config: AudioCaptureConfig) -> Result<Self> {
        let host = cpal::default_host();
        
        let device = if config.is_input {
            match &config.device {
                None => host.default_input_device(),
                Some(device_name) => host
                    .input_devices()?
                    .find(|x| x.name().map_or(false, |y| y == *device_name)),
            }
        } else {
            match &config.device {
                None => host.default_output_device(),
                Some(device_name) => host
                    .output_devices()?
                    .find(|x| x.name().map_or(false, |y| y == *device_name)),
            }
        }
        .ok_or_else(|| anyhow::anyhow!("Failed to find audio device"))?;

        let device_config = if config.is_input {
            device.default_input_config()?
        } else {
            device.default_output_config()?
        };

        let device_name = device.name()?;
        let sample_rate = device_config.sample_rate().0;
        let channels = device_config.channels() as u32;

        println!("CPAL audio device -> {device_name:?} config -> {device_config:?}");

        Ok(Self {
            config,
            device_name,
            sample_rate,
            channels,
        })
    }

    fn get_info(&self) -> AudioCaptureInfo {
        AudioCaptureInfo {
            device_name: self.device_name.clone(),
            sample_rate: self.sample_rate,
            channels: self.channels,
        }
    }

    fn start_capture(&self, cancel_token: CancellationToken) -> Result<mpsc::Receiver<Vec<f32>>> {
        let (tx, rx) = mpsc::channel::<Vec<f32>>();
        
        let config = self.config.clone();
        let channels = self.channels as usize;
        let sample_rate = self.sample_rate as usize;
        let target_sample_rate = self.config.target_sample_rate as f64;
        let resample_ratio = target_sample_rate / sample_rate as f64;
        
        thread::spawn(move || {
            let host = cpal::default_host();
            let device = if config.is_input {
                match &config.device {
                    None => host.default_input_device(),
                    Some(device_name) => host
                        .input_devices()
                        .unwrap()
                        .find(|x| x.name().map_or(false, |y| y == *device_name)),
                }
            } else {
                match &config.device {
                    None => host.default_output_device(),
                    Some(device_name) => host
                        .output_devices()
                        .unwrap()
                        .find(|x| x.name().map_or(false, |y| y == *device_name)),
                }
            }
            .expect("Failed to find audio device");

            let device_config = if config.is_input {
                device.default_input_config().expect("Failed to get input config")
            } else {
                device.default_output_config().expect("Failed to get output config")
            };

            let audio_cancel_token = cancel_token.child_token();
            
            let stream: cpal::Stream = if config.is_input {
                device.build_input_stream(
                    &device_config.config(),
                    move |pcm: &[f32], _: &cpal::InputCallbackInfo| {
                        if audio_cancel_token.is_cancelled() {
                            return;
                        }
                        
                        let mono_pcm = merge_channels(pcm, channels);
                        if !mono_pcm.is_empty() {
                            let resampled_pcm = resample_audio(&mono_pcm, resample_ratio);
                            let _ = tx.send(resampled_pcm);
                        }
                    },
                    move |err| {
                        eprintln!("Audio stream error: {}", err);
                    },
                    None,
                )
            } else {
                device.build_output_stream(
                    &device_config.config(),
                    move |pcm: &mut [f32], _: &cpal::OutputCallbackInfo| {
                        if audio_cancel_token.is_cancelled() {
                            return;
                        }
                        
                        let captured_pcm = merge_channels(pcm, channels);
                        if !captured_pcm.is_empty() {
                            let resampled_pcm = resample_audio(&captured_pcm, resample_ratio);
                            let _ = tx.send(resampled_pcm);
                        }
                    },
                    move |err| {
                        eprintln!("Audio stream error: {}", err);
                    },
                    None,
                )
            }.expect("Failed to create audio stream");

            if let Err(e) = stream.play() {
                eprintln!("Failed to start audio stream: {}", e);
                return;
            }

            while !cancel_token.is_cancelled() {
                thread::sleep(Duration::from_millis(100));
            }

            drop(stream);
            println!("CPAL audio stream stopped");
        });

        Ok(rx)
    }
}

/// Merge multi-channel audio to mono
fn merge_channels(pcm: &[f32], channel_count: usize) -> Vec<f32> {
    if channel_count == 1 {
        return pcm.to_vec();
    }

    let complete_groups = pcm.len() / channel_count;
    let remaining_samples = pcm.len() % channel_count;
    let result_capacity = complete_groups + if remaining_samples > 0 { 1 } else { 0 };
    let mut mono_pcm = Vec::with_capacity(result_capacity);

    // Process complete sample groups
    for i in 0..complete_groups {
        let mut sample_sum = 0.0;
        for ch in 0..channel_count {
            sample_sum += pcm[i * channel_count + ch];
        }
        mono_pcm.push(sample_sum / (channel_count as f32));
    }

    // Process incomplete sample group if exists
    if remaining_samples > 0 {
        let start_idx = complete_groups * channel_count;
        let mut sample_sum = 0.0;
        for ch in 0..remaining_samples {
            sample_sum += pcm[start_idx + ch];
        }
        mono_pcm.push(sample_sum / (remaining_samples as f32));
    }

    mono_pcm
}

/// Simple audio resampling using linear interpolation
fn resample_audio(pcm: &[f32], ratio: f64) -> Vec<f32> {
    if (ratio - 1.0).abs() < f64::EPSILON {
        return pcm.to_vec();
    }

    let output_len = (pcm.len() as f64 * ratio).ceil() as usize;
    let mut output = Vec::with_capacity(output_len);

    for i in 0..output_len {
        let src_index = i as f64 / ratio;
        let src_index_floor = src_index.floor() as usize;
        let src_index_ceil = (src_index_floor + 1).min(pcm.len() - 1);
        let fraction = src_index - src_index_floor as f64;

        if src_index_floor < pcm.len() {
            let sample = if src_index_ceil == src_index_floor {
                pcm[src_index_floor]
            } else {
                let sample1 = pcm[src_index_floor];
                let sample2 = pcm[src_index_ceil];
                sample1 + (sample2 - sample1) * fraction as f32
            };
            output.push(sample);
        }
    }

    output
}

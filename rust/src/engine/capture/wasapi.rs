//! Windows: WASAPI through cpal. An output device is captured in loopback
//! (cpal builds an input stream on it), a microphone directly.

use super::{mix_to_mono, Capture, Device, SourceKind};
use anyhow::{anyhow, Context, Result};
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use local_adapter_sensevoice_asr::{Resampler, TARGET_SAMPLE_RATE};
use std::sync::mpsc;
use std::time::Duration;

pub fn devices() -> Vec<Device> {
    let host = cpal::default_host();
    let default_output = host.default_output_device().and_then(|d| d.id().ok());
    let default_input = host.default_input_device().and_then(|d| d.id().ok());
    let mut out = Vec::new();
    let mut add = |device: cpal::Device, kind: SourceKind, default: &Option<cpal::DeviceId>| {
        let Ok(id) = device.id() else { return };
        let name = device
            .description()
            .map(|description| description.name().to_string())
            .unwrap_or_else(|_| id.to_string());
        out.push(Device {
            is_default: default.as_ref() == Some(&id),
            id: id.to_string(),
            name,
            kind,
        });
    };
    if let Ok(outputs) = host.output_devices() {
        for device in outputs {
            add(device, SourceKind::System, &default_output);
        }
    }
    if let Ok(inputs) = host.input_devices() {
        for device in inputs {
            add(device, SourceKind::Microphone, &default_input);
        }
    }
    out
}

fn find_device(kind: SourceKind, id: Option<&str>) -> Result<cpal::Device> {
    let host = cpal::default_host();
    if let Some(id) = id.filter(|id| !id.is_empty()) {
        let parsed: cpal::DeviceId = id
            .parse()
            .map_err(|error| anyhow!("bad device id {id}: {error:?}"))?;
        if let Some(device) = host.device_by_id(&parsed) {
            return Ok(device);
        }
        tracing::warn!(id, "audio device not found; using the default");
    }
    match kind {
        SourceKind::System => host.default_output_device(),
        SourceKind::Microphone => host.default_input_device(),
    }
    .ok_or_else(|| anyhow!("no default audio device"))
}

pub fn start(kind: SourceKind, id: Option<&str>) -> Result<(Capture, mpsc::Receiver<Vec<f32>>)> {
    let device = find_device(kind, id)?;
    let name = device
        .description()
        .map(|description| description.name().to_string())
        .unwrap_or_default();
    let config = match kind {
        SourceKind::System => device.default_output_config(),
        SourceKind::Microphone => device.default_input_config(),
    }
    .context("audio device configuration")?;
    let rate = config.sample_rate();
    let channels = config.channels() as usize;
    let format = config.sample_format();
    tracing::info!(
        device = name,
        rate,
        channels,
        ?format,
        ?kind,
        "starting audio capture"
    );

    let (tx, rx) = mpsc::channel::<Vec<f32>>();
    let (stop_tx, stop_rx) = mpsc::channel::<()>();
    let (ready_tx, ready_rx) = mpsc::channel::<Result<()>>();
    // The stream is not Send: it lives on its own thread until stopped.
    std::thread::Builder::new()
        .name("fl-capture".into())
        .spawn(move || {
            let mut resampler =
                (rate != TARGET_SAMPLE_RATE).then(|| Resampler::new(rate, TARGET_SAMPLE_RATE));
            let mut interleaved = Vec::new();
            let mut mono = Vec::new();
            let stream = device.build_input_stream_raw(
                &config.config(),
                format,
                move |data: &cpal::Data, _: &cpal::InputCallbackInfo| {
                    interleaved.clear();
                    if let Some(samples) = data.as_slice::<f32>() {
                        interleaved.extend_from_slice(samples);
                    } else if let Some(samples) = data.as_slice::<i16>() {
                        interleaved.extend(samples.iter().map(|&s| s as f32 / 32768.0));
                    } else if let Some(samples) = data.as_slice::<i32>() {
                        interleaved.extend(samples.iter().map(|&s| s as f32 / 2_147_483_648.0));
                    } else {
                        return;
                    }
                    mono.clear();
                    mix_to_mono(&interleaved, channels, &mut mono);
                    let mut out = Vec::with_capacity(mono.len());
                    match &mut resampler {
                        Some(resampler) => resampler.process(&mono, &mut out),
                        None => out.extend_from_slice(&mono),
                    }
                    if !out.is_empty() {
                        let _ = tx.send(out);
                    }
                },
                |error| tracing::warn!(%error, "audio stream error"),
                None,
            );
            let stream = match stream.context("open the audio stream").and_then(|stream| {
                stream.play().context("start the audio stream")?;
                Ok(stream)
            }) {
                Ok(stream) => {
                    let _ = ready_tx.send(Ok(()));
                    stream
                }
                Err(error) => {
                    let _ = ready_tx.send(Err(error));
                    return;
                }
            };
            let _ = stop_rx.recv();
            drop(stream);
            tracing::info!("audio capture stopped");
        })?;
    ready_rx
        .recv_timeout(Duration::from_secs(10))
        .map_err(|_| anyhow!("the audio device did not start"))??;
    Ok((
        Capture::new(name, rate, move || {
            let _ = stop_tx.send(());
        }),
        rx,
    ))
}

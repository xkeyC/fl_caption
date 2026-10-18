//! System audio (what the speakers play) or a microphone, as 16 kHz mono.

#[cfg(target_os = "linux")]
mod pipewire;
#[cfg(windows)]
mod wasapi;

use anyhow::Result;
use std::sync::mpsc;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SourceKind {
    /// Loopback of an output device.
    System,
    Microphone,
}

#[derive(Debug, Clone)]
pub struct Device {
    pub id: String,
    pub name: String,
    pub kind: SourceKind,
    pub is_default: bool,
}

/// A running capture; dropping it stops the stream.
pub struct Capture {
    pub device_name: String,
    pub source_rate: u32,
    stop: Option<Box<dyn FnOnce() + Send>>,
}

impl Capture {
    fn new(device_name: String, source_rate: u32, stop: impl FnOnce() + Send + 'static) -> Self {
        Self {
            device_name,
            source_rate,
            stop: Some(Box::new(stop)),
        }
    }
}

impl Drop for Capture {
    fn drop(&mut self) {
        if let Some(stop) = self.stop.take() {
            stop();
        }
    }
}

pub fn devices() -> Vec<Device> {
    #[cfg(windows)]
    return wasapi::devices();
    #[cfg(target_os = "linux")]
    return pipewire::devices();
    #[allow(unreachable_code)]
    Vec::new()
}

/// Starts capturing `device` (`None`: the default of `kind`); chunks of
/// 16 kHz mono samples arrive on the receiver.
pub fn start(
    kind: SourceKind,
    device: Option<&str>,
) -> Result<(Capture, mpsc::Receiver<Vec<f32>>)> {
    #[cfg(windows)]
    return wasapi::start(kind, device);
    #[cfg(target_os = "linux")]
    return pipewire::start(kind, device);
    #[allow(unreachable_code)]
    {
        let _ = (kind, device);
        anyhow::bail!("audio capture is not supported on this platform")
    }
}

/// Mixes interleaved frames down to mono.
pub(crate) fn mix_to_mono(interleaved: &[f32], channels: usize, out: &mut Vec<f32>) {
    let channels = channels.max(1);
    out.extend(
        interleaved
            .chunks(channels)
            .map(|frame| frame.iter().sum::<f32>() / frame.len() as f32),
    );
}

/// A file decoded and delivered in 20 ms chunks at real-time pace, as a
/// device would (tests and demos).
pub fn play_file(path: &std::path::Path) -> Result<(Capture, mpsc::Receiver<Vec<f32>>)> {
    use local_adapter_sensevoice_asr::AudioStream;
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::sync::Arc;
    use std::time::{Duration, Instant};
    let mut stream = AudioStream::open(path).map_err(|error| anyhow::anyhow!("{error}"))?;
    let (tx, rx) = mpsc::channel();
    let stop = Arc::new(AtomicBool::new(false));
    let stopped = stop.clone();
    std::thread::Builder::new()
        .name("fl-file-source".into())
        .spawn(move || {
            const CHUNK: usize = 320;
            let started = Instant::now();
            let mut sent = 0usize;
            let mut pending = Vec::new();
            loop {
                if stopped.load(Ordering::Relaxed) {
                    return;
                }
                while pending.len() < CHUNK {
                    match stream.read(&mut pending) {
                        Ok(true) => {}
                        _ => break,
                    }
                }
                if pending.is_empty() {
                    return;
                }
                let take = pending.len().min(CHUNK);
                let chunk: Vec<f32> = pending.drain(..take).collect();
                sent += chunk.len();
                if tx.send(chunk).is_err() {
                    return;
                }
                let due = Duration::from_secs_f64(sent as f64 / 16_000.0);
                if let Some(wait) = due.checked_sub(started.elapsed()) {
                    std::thread::sleep(wait);
                }
            }
        })?;
    Ok((
        Capture::new(path.display().to_string(), 16_000, move || {
            stop.store(true, Ordering::Relaxed);
        }),
        rx,
    ))
}

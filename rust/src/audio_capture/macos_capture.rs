use super::traits::{AudioCapture, AudioCaptureConfig, AudioCaptureInfo};
use anyhow::Result;
use std::sync::mpsc;
use tokio_util::sync::CancellationToken;

pub struct MacosAudioCapture;

impl AudioCapture for MacosAudioCapture {
    fn new(_config: AudioCaptureConfig) -> Result<Self> {
        anyhow::bail!("Audio capture is not supported on macOS platform")
    }

    fn get_info(&self) -> AudioCaptureInfo {
        unreachable!("macOS audio capture is not supported")
    }

    fn start_capture(&self, _cancel_token: CancellationToken) -> Result<mpsc::Receiver<Vec<f32>>> {
        unreachable!("macOS audio capture is not supported")
    }
}

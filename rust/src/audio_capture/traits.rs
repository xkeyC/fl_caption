use std::sync::mpsc;
use anyhow::Result;
use tokio_util::sync::CancellationToken;

/// Audio capture configuration
#[derive(Debug, Clone)]
pub struct AudioCaptureConfig {
    /// Audio device name (None for default device)
    pub device: Option<String>,
    /// Whether to use input device (true) or output device (false)
    pub is_input: bool,
    /// Target sample rate (Hz)
    pub target_sample_rate: u32,
    /// Target channel count
    pub target_channels: u32,
}

impl Default for AudioCaptureConfig {
    fn default() -> Self {
        Self {
            device: None,
            is_input: false, // Default to output device (speakers)
            target_sample_rate: 16000,
            target_channels: 1,
        }
    }
}

/// Audio capture information
#[derive(Debug, Clone)]
pub struct AudioCaptureInfo {
    pub device_name: String,
    pub sample_rate: u32,
    pub channels: u32,
}

/// Trait for audio capture implementations
pub trait AudioCapture: Send + Sync {
    /// Create a new audio capture instance
    fn new(config: AudioCaptureConfig) -> Result<Self> where Self: Sized;
    
    /// Get audio capture information
    fn get_info(&self) -> AudioCaptureInfo;
    
    /// Start audio capture
    /// Returns a receiver for audio samples (f32, mono, 16kHz)
    fn start_capture(&self, cancel_token: CancellationToken) -> Result<mpsc::Receiver<Vec<f32>>>;
}

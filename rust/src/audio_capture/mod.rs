pub mod traits;

#[cfg(target_os = "windows")]
pub mod cpal_capture;

#[cfg(target_os = "linux")]
pub mod pipewire_capture;

#[cfg(target_os = "macos")]
pub mod macos_capture;

pub use traits::*;

#[cfg(target_os = "windows")]
pub use cpal_capture::CpalAudioCapture as PlatformAudioCapture;

#[cfg(target_os = "linux")]
pub use pipewire_capture::PipewireAudioCapture as PlatformAudioCapture;

#[cfg(target_os = "macos")]
pub use macos_capture::MacosAudioCapture as PlatformAudioCapture;

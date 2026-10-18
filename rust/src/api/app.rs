//! App start-up: logging, ONNX Runtime, the model store; system facts.

use crate::engine::{capture, catalog, lang, runtime, store};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::OnceLock;

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

pub struct RuntimeInfo {
    pub ort_path: Option<String>,
    /// ONNX Runtime with the CUDA provider (the GPU runtime package).
    pub gpu_runtime: bool,
    pub error: Option<String>,
    pub gpus: Vec<GpuInfo>,
    pub log_file: String,
    pub cuda_context_mb: u64,
}

pub struct GpuInfo {
    pub name: String,
    pub total_mb: u64,
    pub used_mb: u64,
    pub driver: String,
}

static LOG_GUARD: OnceLock<tracing_appender::non_blocking::WorkerGuard> = OnceLock::new();

/// Call once at start-up. `search_roots`: directories holding `runtime/`
/// besides the executable's (the working directory during development).
pub fn init_engine(log_dir: String, search_roots: Vec<String>) -> RuntimeInfo {
    let log_file = PathBuf::from(&log_dir).join("fl_caption.log");
    if LOG_GUARD.get().is_none() {
        let _ = std::fs::create_dir_all(&log_dir);
        let appender = tracing_appender::rolling::never(&log_dir, "fl_caption.log");
        let (writer, guard) = tracing_appender::non_blocking(appender);
        let filter = tracing_subscriber::EnvFilter::try_from_env("FL_CAPTION_LOG")
            .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info,ort=warn"));
        let _ = tracing_subscriber::fmt()
            .with_env_filter(filter)
            .with_writer(writer)
            .with_ansi(false)
            .try_init();
        let _ = LOG_GUARD.set(guard);
        tracing::info!(
            version = env!("CARGO_PKG_VERSION"),
            "fl_caption engine starting"
        );
    }
    let mut roots: Vec<PathBuf> = std::env::current_exe()
        .ok()
        .and_then(|exe| exe.parent().map(PathBuf::from))
        .into_iter()
        .collect();
    roots.extend(search_roots.into_iter().map(PathBuf::from));
    let state = runtime::init(&roots);
    RuntimeInfo {
        ort_path: state.ort_path.map(|path| path.display().to_string()),
        gpu_runtime: state.gpu_build,
        error: state.error,
        gpus: gpu_info(),
        log_file: log_file.display().to_string(),
        cuda_context_mb: catalog::CUDA_CONTEXT_MB,
    }
}

pub fn gpu_info() -> Vec<GpuInfo> {
    runtime::gpus()
        .into_iter()
        .map(|gpu| GpuInfo {
            name: gpu.name,
            total_mb: gpu.total_mb,
            used_mb: gpu.used_mb,
            driver: gpu.driver,
        })
        .collect()
}

pub struct ModelPath {
    pub id: String,
    pub dir: String,
}

/// Where models are kept; `imported`: models used from directories
/// elsewhere. `hf_endpoint`: a Hugging Face mirror (e.g.
/// https://hf-mirror.com), empty for huggingface.co.
pub fn configure_models(root: String, imported: Vec<ModelPath>, hf_endpoint: String) {
    let overrides: HashMap<String, PathBuf> = imported
        .into_iter()
        .map(|path| (path.id, PathBuf::from(path.dir)))
        .collect();
    store::configure(PathBuf::from(root), overrides, Some(hf_endpoint));
}

pub struct LanguageInfo {
    pub code: String,
    pub zh: String,
    pub en: String,
    pub native: String,
}

#[flutter_rust_bridge::frb(sync)]
pub fn languages() -> Vec<LanguageInfo> {
    lang::LANGUAGES
        .iter()
        .map(|language| LanguageInfo {
            code: language.code.into(),
            zh: language.zh.into(),
            en: language.en.into(),
            native: language.native.into(),
        })
        .collect()
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AudioSourceKind {
    System,
    Microphone,
}

impl From<AudioSourceKind> for capture::SourceKind {
    fn from(kind: AudioSourceKind) -> Self {
        match kind {
            AudioSourceKind::System => Self::System,
            AudioSourceKind::Microphone => Self::Microphone,
        }
    }
}

pub struct AudioDevice {
    pub id: String,
    pub name: String,
    pub kind: AudioSourceKind,
    pub is_default: bool,
}

pub fn audio_devices() -> Vec<AudioDevice> {
    capture::devices()
        .into_iter()
        .map(|device| AudioDevice {
            id: device.id,
            name: device.name,
            kind: match device.kind {
                capture::SourceKind::System => AudioSourceKind::System,
                capture::SourceKind::Microphone => AudioSourceKind::Microphone,
            },
            is_default: device.is_default,
        })
        .collect()
}

/// ffmpeg for formats symphonia cannot read: the configured one, beside the
/// executable, or on PATH.
pub fn find_ffmpeg(configured: Option<String>) -> Option<String> {
    crate::engine::filejob::find_ffmpeg(configured.as_deref().map(std::path::Path::new))
        .map(|path| path.display().to_string())
}

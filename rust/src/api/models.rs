//! The model catalog, installation state, downloads and imports.

use crate::engine::{catalog, pool, store};
use crate::frb_generated::StreamSink;
use std::path::Path;
use std::time::{Duration, Instant};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ModelCategory {
    Asr,
    Translator,
}

pub struct ModelInfo {
    pub id: String,
    pub name: String,
    pub kind: ModelCategory,
    pub description_zh: String,
    pub description_en: String,
    pub size_mb: u64,
    pub vram_mb: u64,
    pub ram_mb: u64,
    pub kv_kb_per_token: u64,
    pub default_context: u64,
    pub gpu_only: bool,
    pub cpu_ok: bool,
    pub hotwords: bool,
    pub languages: String,
    pub license: String,
    pub homepage: String,
    pub recommended: bool,
    /// Downloadable now (exported packages wait for their hosting).
    pub downloadable: bool,
    pub installed: bool,
    pub imported: bool,
    pub downloading: bool,
    pub dir: String,
    pub bytes_on_disk: u64,
    /// Dedicated translation model (Hy-MT2 prompts) rather than a chat LLM.
    pub translation_model: bool,
}

pub fn list_models() -> Vec<ModelInfo> {
    catalog::catalog()
        .into_iter()
        .map(|entry| {
            let state = store::install_state(&entry).ok();
            ModelInfo {
                id: entry.id.into(),
                name: entry.name.into(),
                kind: match entry.kind {
                    catalog::ModelKind::Asr => ModelCategory::Asr,
                    catalog::ModelKind::Translator => ModelCategory::Translator,
                },
                description_zh: entry.description_zh.into(),
                description_en: entry.description_en.into(),
                size_mb: entry.size_mb,
                vram_mb: entry.vram_mb,
                ram_mb: entry.ram_mb,
                kv_kb_per_token: entry.kv_kb_per_token,
                default_context: entry.default_context,
                gpu_only: entry.gpu_only,
                cpu_ok: entry.cpu_ok,
                hotwords: entry.hotwords,
                languages: entry.languages.into(),
                license: entry.license.into(),
                homepage: entry.homepage.into(),
                recommended: entry.recommended,
                downloadable: entry.downloadable(),
                installed: state.as_ref().is_some_and(|s| s.installed),
                imported: state.as_ref().is_some_and(|s| s.imported),
                downloading: store::downloading(entry.id),
                dir: state
                    .as_ref()
                    .map(|s| s.dir.display().to_string())
                    .unwrap_or_default(),
                bytes_on_disk: state.as_ref().map(|s| s.bytes_on_disk).unwrap_or(0),
                translation_model: entry.engine == catalog::Engine::HyMt,
            }
        })
        .collect()
}

pub struct DownloadEvent {
    pub id: String,
    pub file: String,
    pub file_index: u32,
    pub file_count: u32,
    pub downloaded: u64,
    pub total: u64,
    pub speed: u64,
    pub done: bool,
    pub error: Option<String>,
}

/// Downloads a model; events until one with `done`.
pub fn download_model(id: String, sink: StreamSink<DownloadEvent>) {
    std::thread::spawn(move || {
        let mut last = Instant::now() - Duration::from_secs(1);
        let result = store::download(&id, |progress| {
            if last.elapsed() < Duration::from_millis(200) {
                return;
            }
            last = Instant::now();
            let _ = sink.add(DownloadEvent {
                id: id.clone(),
                file: progress.file.clone(),
                file_index: progress.file_index as u32,
                file_count: progress.file_count as u32,
                downloaded: progress.downloaded,
                total: progress.total,
                speed: progress.speed,
                done: false,
                error: None,
            });
        });
        let _ = sink.add(DownloadEvent {
            id: id.clone(),
            file: String::new(),
            file_index: 0,
            file_count: 0,
            downloaded: 0,
            total: 0,
            speed: 0,
            done: true,
            error: result.err().map(|error| format!("{error:#}")),
        });
    });
}

pub fn cancel_download(id: String) {
    store::cancel_download(&id);
}

pub fn delete_model(id: String) -> anyhow::Result<()> {
    let entry = catalog::find(&id).ok_or_else(|| anyhow::anyhow!("unknown model {id}"))?;
    pool::unload_all();
    store::delete(&entry)
}

/// Checks that `dir` holds the model's package (before importing it).
pub fn validate_model_dir(id: String, dir: String) -> anyhow::Result<()> {
    let entry = catalog::find(&id).ok_or_else(|| anyhow::anyhow!("unknown model {id}"))?;
    store::validate_package(&entry, Path::new(&dir))
}

pub struct LoadedModel {
    pub id: String,
    pub provider: String,
}

pub fn loaded_models() -> Vec<LoadedModel> {
    pool::loaded()
        .into_iter()
        .map(|loaded| LoadedModel {
            id: loaded.id,
            provider: loaded.provider,
        })
        .collect()
}

pub fn unload_models() {
    pool::unload_all();
}

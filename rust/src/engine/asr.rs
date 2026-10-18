//! Speech recognition on infra's adapters, one speech segment at a time
//! (fl_caption runs its own VAD).

use super::catalog::{CatalogEntry, Engine};
use anyhow::{anyhow, bail, Result};
use local_adapter_fun_asr_nano::FunAsrNanoAdapter;
use local_adapter_sensevoice_asr::{RecognizedText, SenseVoiceAsrAdapter};
use local_core::ModelSpec;
use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::path::Path;

pub enum AsrEngine {
    SenseVoice(Box<SenseVoiceAsrAdapter>),
    Nano(Box<FunAsrNanoAdapter>),
}

#[derive(Debug, Clone, Default)]
pub struct AsrOptions {
    /// Fun-ASR-Nano only.
    pub hotwords: Vec<String>,
    /// Fun-ASR-Nano only: `zh`, `en`, `ja` (others: any).
    pub language: Option<String>,
}

#[derive(Debug, Clone, Default)]
pub struct Token {
    pub start_ms: u64,
    pub end_ms: u64,
    pub text: String,
    pub starts_word: bool,
}

#[derive(Debug, Clone, Default)]
pub struct Recognized {
    pub text: String,
    /// The language tag SenseVoice reports (`zh`, `en`, `yue`, `ja`, `ko`).
    pub language: Option<String>,
    pub emotion: Option<String>,
    pub events: Vec<String>,
    /// Token times relative to the segment start (SenseVoice only).
    pub tokens: Vec<Token>,
}

impl From<RecognizedText> for Recognized {
    fn from(text: RecognizedText) -> Self {
        Self {
            text: text.text,
            language: text.language,
            emotion: text.emotion,
            events: text.events,
            tokens: text
                .tokens
                .into_iter()
                .map(|token| Token {
                    start_ms: token.start_ms,
                    end_ms: token.end_ms,
                    text: token.text,
                    starts_word: token.starts_word,
                })
                .collect(),
        }
    }
}

/// infra's model spec for a catalog entry installed in `dir`.
pub fn model_spec(entry: &CatalogEntry, dir: &Path, use_gpu: bool) -> Result<ModelSpec> {
    let providers = if use_gpu {
        vec!["cuda", "cpu"]
    } else {
        vec!["cpu"]
    };
    let mut metadata = entry.metadata();
    metadata.insert("auto_select".into(), Value::Bool(false));
    let spec = json!({
        "id": entry.id,
        "name": entry.name,
        "adapter": entry.adapter(),
        "backend": "ort",
        "artifacts": [{ "type": "local", "path": dir }],
        "runtime": { "provider_order": providers },
        "metadata": metadata,
    });
    serde_json::from_value(spec).map_err(|error| anyhow!("model spec for {}: {error}", entry.id))
}

impl AsrEngine {
    pub fn load(entry: &CatalogEntry, dir: &Path, use_gpu: bool) -> Result<Self> {
        if entry.gpu_only && !use_gpu {
            bail!("{} runs on an NVIDIA GPU only", entry.name);
        }
        let spec = model_spec(entry, dir, use_gpu)?;
        let engine = match entry.engine {
            Engine::SenseVoice => Self::SenseVoice(Box::new(
                SenseVoiceAsrAdapter::load(&spec).map_err(|error| anyhow!("{error}"))?,
            )),
            Engine::FunAsrNano => Self::Nano(Box::new(
                FunAsrNanoAdapter::load(&spec).map_err(|error| anyhow!("{error}"))?,
            )),
            Engine::HyMt | Engine::ChatLlm => bail!("{} is not a speech model", entry.id),
        };
        tracing::info!(
            model = entry.id,
            provider = engine.provider(),
            "ASR model loaded"
        );
        Ok(engine)
    }

    /// The provider the recognizer itself runs on (`cuda` or `cpu`).
    pub fn provider(&self) -> &'static str {
        let provider = match self {
            Self::SenseVoice(adapter) => adapter.provider_report().provider,
            Self::Nano(adapter) => adapter.provider_report().llm.provider,
        };
        provider_name(provider)
    }

    pub fn supports_hotwords(&self) -> bool {
        matches!(self, Self::Nano(_))
    }

    /// One speech segment (16 kHz mono).
    pub fn recognize(&mut self, samples: &[f32], options: &AsrOptions) -> Result<Recognized> {
        let recognized = match self {
            Self::SenseVoice(adapter) => adapter.recognize_samples(samples),
            Self::Nano(adapter) => {
                let mut params = BTreeMap::new();
                let hotwords: Vec<&str> = options
                    .hotwords
                    .iter()
                    .map(|word| word.trim())
                    .filter(|word| !word.is_empty() && !word.contains("<|") && !word.contains("|>"))
                    .take(200)
                    .collect();
                if !hotwords.is_empty() {
                    params.insert("hotwords".to_string(), json!(hotwords));
                }
                if let Some(language) = options
                    .language
                    .as_deref()
                    .filter(|language| matches!(*language, "zh" | "en" | "ja"))
                {
                    params.insert("language".to_string(), json!(language));
                }
                adapter.recognize_samples_with_params(samples, &params)
            }
        };
        let mut recognized: Recognized = recognized.map_err(|error| anyhow!("{error}"))?.into();
        recognized.text = recognized.text.trim().to_string();
        Ok(recognized)
    }
}

pub fn provider_name(provider: local_backend_ort::ProviderKind) -> &'static str {
    match provider {
        local_backend_ort::ProviderKind::Cuda => "cuda",
        local_backend_ort::ProviderKind::Dml => "directml",
        local_backend_ort::ProviderKind::Trt => "tensorrt",
        local_backend_ort::ProviderKind::Cpu => "cpu",
    }
}

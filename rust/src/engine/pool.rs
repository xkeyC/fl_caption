//! The loaded models, shared by live captions and file jobs: one ASR model
//! and one translation model at a time (loading another drops the old one
//! first, so GPU memory never holds both).

use super::asr::{self, AsrEngine};
use super::catalog::{self, ModelKind};
use super::store;
use anyhow::{anyhow, bail, Result};
use local_adapter_qwen3_chat::Qwen3ChatAdapter;
use std::sync::{Arc, Mutex};

pub type SharedAsr = Arc<Mutex<AsrEngine>>;
pub type SharedChat = Arc<Mutex<Qwen3ChatAdapter>>;

struct Slot<T> {
    key: String,
    model: Arc<Mutex<T>>,
    provider: &'static str,
}

static ASR: Mutex<Option<Slot<AsrEngine>>> = Mutex::new(None);
static CHAT: Mutex<Option<Slot<Qwen3ChatAdapter>>> = Mutex::new(None);

#[derive(Debug, Clone)]
pub struct Loaded {
    pub id: String,
    pub provider: String,
}

pub fn asr(id: &str, use_gpu: bool) -> Result<SharedAsr> {
    let entry = catalog::find(id).ok_or_else(|| anyhow!("unknown model {id}"))?;
    if entry.kind != ModelKind::Asr {
        bail!("{id} is not a speech model");
    }
    let key = format!("{id}@{}", if use_gpu { "gpu" } else { "cpu" });
    let mut slot = ASR.lock().unwrap_or_else(|e| e.into_inner());
    if let Some(current) = slot.as_ref().filter(|current| current.key == key) {
        return Ok(current.model.clone());
    }
    // Free the old model's memory before loading the new one.
    *slot = None;
    let dir = store::model_dir(id)?;
    let engine = AsrEngine::load(&entry, &dir, use_gpu)?;
    let provider = engine.provider();
    let model = Arc::new(Mutex::new(engine));
    *slot = Some(Slot {
        key,
        model: model.clone(),
        provider,
    });
    Ok(model)
}

pub fn chat(id: &str, use_gpu: bool, context: usize) -> Result<SharedChat> {
    let entry = catalog::find(id).ok_or_else(|| anyhow!("unknown model {id}"))?;
    if entry.kind != ModelKind::Translator {
        bail!("{id} is not a translation model");
    }
    let key = format!("{id}@{}/{context}", if use_gpu { "gpu" } else { "cpu" });
    let mut slot = CHAT.lock().unwrap_or_else(|e| e.into_inner());
    if let Some(current) = slot.as_ref().filter(|current| current.key == key) {
        return Ok(current.model.clone());
    }
    *slot = None;
    let dir = store::model_dir(id)?;
    let mut spec = asr::model_spec(&entry, &dir, use_gpu)?;
    spec.metadata
        .insert("max_context".into(), serde_json::json!(context));
    let adapter = Qwen3ChatAdapter::load(&spec).map_err(|error| anyhow!("{error}"))?;
    let provider = asr::provider_name(adapter.provider_report().provider);
    tracing::info!(model = id, provider, context, "translation model loaded");
    let model = Arc::new(Mutex::new(adapter));
    *slot = Some(Slot {
        key,
        model: model.clone(),
        provider,
    });
    Ok(model)
}

pub fn loaded() -> Vec<Loaded> {
    let mut out = Vec::new();
    for (key, provider) in [
        ASR.lock()
            .unwrap_or_else(|e| e.into_inner())
            .as_ref()
            .map(|slot| (slot.key.clone(), slot.provider)),
        CHAT.lock()
            .unwrap_or_else(|e| e.into_inner())
            .as_ref()
            .map(|slot| (slot.key.clone(), slot.provider)),
    ]
    .into_iter()
    .flatten()
    {
        out.push(Loaded {
            id: key.split('@').next().unwrap_or_default().to_string(),
            provider: provider.to_string(),
        });
    }
    out
}

/// Drops models nobody holds (a live session or file job keeps its own
/// handle while it runs).
pub fn release_unused() {
    let mut asr = ASR.lock().unwrap_or_else(|e| e.into_inner());
    if asr
        .as_ref()
        .is_some_and(|slot| Arc::strong_count(&slot.model) == 1)
    {
        *asr = None;
    }
    drop(asr);
    let mut chat = CHAT.lock().unwrap_or_else(|e| e.into_inner());
    if chat
        .as_ref()
        .is_some_and(|slot| Arc::strong_count(&slot.model) == 1)
    {
        *chat = None;
    }
}

/// Drops the pool's handles; models in use stay until their users finish.
pub fn unload_all() {
    *ASR.lock().unwrap_or_else(|e| e.into_inner()) = None;
    *CHAT.lock().unwrap_or_else(|e| e.into_inner()) = None;
}

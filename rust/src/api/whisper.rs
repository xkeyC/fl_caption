use crate::audio_models;
use crate::frb_generated::StreamSink;
use once_cell::sync::Lazy;
use std::collections::HashMap;
use std::sync::Mutex;
use uuid::Uuid;

pub type CancellationToken = tokio_util::sync::CancellationToken;

static TOKEN_STORE: Lazy<Mutex<HashMap<String, CancellationToken>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));

pub fn create_cancellation_token() -> String {
    let token = CancellationToken::new();
    let uuid = Uuid::new_v4().to_string();

    if let Ok(mut store) = TOKEN_STORE.lock() {
        store.insert(uuid.clone(), token);
    }

    uuid
}

pub fn cancel_cancellation_token(token_id: String) {
    if let Ok(mut store) = TOKEN_STORE.lock() {
        if let Some(token) = store.remove(&token_id) {
            token.cancel();
        }
    }
}

pub struct WhisperClient {
    pub models: HashMap<String, String>,
    pub config: String,
    pub tokenizer: Vec<u8>,
    pub is_multilingual: bool,
    pub is_quantized: bool,
    pub model_type: String,
}

impl WhisperClient {
    pub fn new(
        models: HashMap<String, String>,
        config: String,
        tokenizer: Vec<u8>,
        is_multilingual: bool,
        is_quantized: bool,
        model_type: String,
    ) -> Self {
        Self {
            models,
            config,
            tokenizer,
            is_multilingual,
            is_quantized,
            model_type,
        }
    }
}

pub async fn launch_caption(
    _whisper_client: WhisperClient,
    stream_sink: StreamSink<Vec<audio_models::model::Segment>>,
    _audio_device: Option<String>,
    _audio_device_is_input: Option<bool>,
    _audio_language: Option<String>,
    _cancel_token_id: String,
    _with_timestamps: Option<bool>,
    _verbose: Option<bool>,
    _try_with_cuda: Option<bool>,
    _whisper_max_audio_duration: Option<u32>,
    _inference_interval: Option<u64>,
    _whisper_default_max_decode_tokens: Option<usize>,
    _whisper_temperature: Option<f32>,
    _vad_model_path: Option<String>,
    _vad_filters_value: Option<f32>,
) -> anyhow::Result<()> {
    let cancel_token = if let Ok(store) = TOKEN_STORE.lock() {
        store.get(&_cancel_token_id).cloned()
    } else {
        None
    };
    
    log::info!("[launch_caption] Starting Python call");
    let result = crate::python::call_hello_world()
        .map_err(|e| anyhow::anyhow!("Python error: {}", e))?;
    log::info!("[launch_caption] Python call returned: {}", result);
    
    let segment = audio_models::model::Segment {
        start: 0.0,
        duration: 0.0,
        dr: audio_models::model::DecodingResult {
            tokens: vec![],
            text: result,
            avg_logprob: 0.0,
            no_speech_prob: 0.0,
            temperature: 0.0,
            compression_ratio: 0.0,
        },
        reasoning_duration: None,
        reasoning_lang: None,
        audio_duration: None,
        status: audio_models::model::WhisperStatus::Working,
    };
    
    log::info!("[launch_caption] Sleeping for 2 seconds");
    tokio::time::sleep(std::time::Duration::from_secs(2)).await;
    log::info!("[launch_caption] Sending segment via stream_sink");
    
    stream_sink.add(vec![segment]).unwrap();
    log::info!("[launch_caption] Segment sent");
    
    if let Some(token) = cancel_token {
        log::info!("[launch_caption] Waiting for cancellation token");
        token.cancelled().await;
        log::info!("[launch_caption] Cancellation token triggered");
    }
    
    Ok(())
}

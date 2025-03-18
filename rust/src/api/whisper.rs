use crate::{frb_generated::StreamSink, whisper_caption};
use once_cell::sync::Lazy;
use std::collections::HashMap;
use std::sync::Mutex;
use std::time::Duration;
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
    pub whisper_model: String,
    pub whisper_config: String,
    pub whisper_tokenizer: Vec<u8>,
    pub is_multilingual: bool,
    pub is_quantized: bool,
}

impl WhisperClient {
    pub fn new(
        whisper_model: String,
        whisper_config: String,
        whisper_tokenizer: Vec<u8>,
        is_multilingual: bool,
        is_quantized: bool,
    ) -> Self {
        Self {
            whisper_model,
            whisper_config,
            whisper_tokenizer,
            is_multilingual,
            is_quantized,
        }
    }
}

pub async fn launch_caption(
    whisper_client: WhisperClient,
    stream_sink: StreamSink<Vec<whisper_caption::whisper::Segment>>,
    audio_device: Option<String>,
    audio_device_is_input: Option<bool>,
    audio_language: Option<String>,
    cancel_token_id: String,
    with_timestamps: Option<bool>,
    verbose: Option<bool>,
    try_with_cuda: Option<bool>,
) -> anyhow::Result<()> {
    let stream_sink_clone = stream_sink.clone();
    let cancel_token = if let Ok(store) = TOKEN_STORE.lock() {
        store
            .get(&cancel_token_id)
            .cloned()
            .unwrap_or_else(CancellationToken::new)
    } else {
        return Err(anyhow::Error::msg("Failed to get cancellation token"));
    };

    let r = whisper_caption::launch_caption(
        whisper_client.whisper_model,
        &whisper_client.whisper_config,
        whisper_client.is_quantized,
        whisper_client.whisper_tokenizer,
        audio_device,
        audio_device_is_input,
        audio_language,
        Some(whisper_client.is_multilingual),
        cancel_token,
        with_timestamps,
        verbose,
        try_with_cuda.unwrap_or(false),
        Some(Duration::from_millis(1500)),
        Some(128),
        move |segments| {
            let _ = stream_sink.add(segments);
        },
    )
    .await;
    if let Err(e) = r {
        stream_sink_clone
            .add_error(format!("Error in whisper captioning: {e}"))
            .unwrap_or(());
    }
    Ok(())
}

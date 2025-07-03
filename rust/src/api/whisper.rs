use crate::onnx_models;
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
    pub models: HashMap<String, String>,
    pub config: String,
    pub tokenizer: Vec<u8>,
    pub is_multilingual: bool,
    pub is_quantized: bool,
}

impl WhisperClient {
    pub fn new(
        models: HashMap<String, String>,
        config: String,
        tokenizer: Vec<u8>,
        is_multilingual: bool,
        is_quantized: bool,
    ) -> Self {
        Self {
            models,
            config,
            tokenizer,
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
    whisper_max_audio_duration: Option<u32>, // 音频上下文长度
    inference_interval: Option<u64>,         // 推理间隔时间
    whisper_default_max_decode_tokens: Option<usize>, // 最大推理token长度
    whisper_temperature: Option<f32>,        // 温度参数
    vad_model_path: Option<String>,          // VAD模型路径
    vad_filters_value: Option<f32>,          // VAD过滤值
) -> anyhow::Result<()> {
    let stream_sink_clone = stream_sink.clone();

    let cancel_token = {
        let store = TOKEN_STORE.lock().unwrap();
        if let Some(token) = store.get(&cancel_token_id) {
            token.clone()
        } else {
            return Err(anyhow::anyhow!("Invalid cancellation token ID"));
        }
    };

    let p = whisper_caption::LaunchCaptionParams {
        models: whisper_client.models,
        config_data: whisper_client.config,
        is_quantized: whisper_client.is_quantized,
        tokenizer_data: whisper_client.tokenizer,
        audio_device,
        audio_device_is_input,
        audio_language,
        is_multilingual: Some(whisper_client.is_multilingual),
        cancel_token,
        with_timestamps,
        verbose,
        try_with_cuda: try_with_cuda.unwrap_or(false),
        inference_timeout: inference_interval.map(|ms| Duration::from_millis(ms)),
        max_tokens_per_segment: whisper_default_max_decode_tokens,
        whisper_max_audio_duration,
        inference_interval_ms: inference_interval,
        whisper_temperature,
        vad_model_path,
        vad_filters_value,
    };

    let r = if p.config_data.ends_with("_onnx") {
        onnx_models::launch_caption(p, move |segments| {
            let _ = stream_sink.add(segments);
        })
        .await
    } else {
        whisper_caption::launch_caption(p, move |segments| {
            let _ = stream_sink.add(segments);
        })
        .await
    };
    if let Err(e) = r {
        stream_sink_clone
            .add_error(format!("Error in whisper captioning: {e}"))
            .unwrap_or(());
    }
    Ok(())
}

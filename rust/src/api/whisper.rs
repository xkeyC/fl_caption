use crate::{frb_generated::StreamSink, whisper_caption};

pub type CancellationToken = tokio_util::sync::CancellationToken;

pub fn create_cancellation_token() -> CancellationToken {
    CancellationToken::new()
}

pub fn cancel_cancellation_token(token: CancellationToken) {
    token.cancel();
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
    cancel_token: CancellationToken,
    with_timestamps: Option<bool>,
    verbose: Option<bool>,
) -> anyhow::Result<()> {
    whisper_caption::launch_caption(
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
        move |segments| {
            let _ = stream_sink.add(segments);
        },
    )
    .await
}

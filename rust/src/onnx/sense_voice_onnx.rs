use crate::whisper_caption::{self, whisper::Segment};

use sherpa_rs::{
    sense_voice::{SenseVoiceConfig, SenseVoiceRecognizer},
};

pub fn launch_caption<F>(
    params: whisper_caption::LaunchCaptionParams,
    mut result_callback: F,
) -> anyhow::Result<()>
where
    F: FnMut(Vec<Segment>) + Send + 'static,
{
       let config = SenseVoiceConfig {
        model: "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/model.int8.onnx".into(),
        tokens: "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/tokens.txt".into(),
        provider: Some(provider),

        ..Default::default()
    };
    // Implement the ONNX model inference logic here
    Ok(())
}

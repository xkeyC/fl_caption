mod sense_voice_onnx;


use crate::whisper_caption::{self, whisper::Segment};

pub async fn launch_caption<F>(
    params: whisper_caption::LaunchCaptionParams,
    mut result_callback: F,
) -> anyhow::Result<()>
where
    F: FnMut(Vec<Segment>) + Send + 'static,
{
    if params.config_data.eq("sense-voice_onnx") {
        // Handle sense-voice_onnx model
        sense_voice_onnx::launch_caption(params, move |segments| {
            result_callback(segments);
        })?
    }
    Err(anyhow::anyhow!("Unsupported model"))
}

use crate::whisper_caption::{self, whisper::Segment};

pub fn launch_caption<F>(
    params: whisper_caption::LaunchCaptionParams,
    mut result_callback: F,
) -> anyhow::Result<()>
where
    F: FnMut(Vec<Segment>) + Send + 'static,
{
    // Implement the ONNX model inference logic here
    Ok(())
}

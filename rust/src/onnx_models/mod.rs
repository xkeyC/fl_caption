pub mod vad;

use ort::session::Session;

pub fn init_model(model_path: String, _try_gpu: bool) -> anyhow::Result<Session> {
    let session = Session::builder()
        .map_err(|e| anyhow::anyhow!("Failed to create session builder: {:?}", e))?
        .commit_from_file(model_path)
        .map_err(|e| anyhow::anyhow!("Failed to load model: {:?}", e))?;
    Ok(session)
}

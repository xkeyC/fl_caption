use ort::execution_providers::ExecutionProviderDispatch;
use ort::session::Session;

mod sense_voice;

#[cfg(target_os = "macos")]
use ort::execution_providers::CoreMLExecutionProvider;

#[cfg(any(target_os = "linux", target_os = "windows"))]
use ort::execution_providers::{
    CUDAExecutionProvider, TensorRTExecutionProvider, WebGPUExecutionProvider,
};

#[cfg(target_os = "windows")]
use ort::execution_providers::DirectMLExecutionProvider;

use crate::whisper_caption::{whisper::Segment, LaunchCaptionParams};

pub async fn launch_caption<F>(
    params: LaunchCaptionParams,
    mut result_callback: F,
) -> anyhow::Result<()>
where
    F: FnMut(Vec<Segment>) + Send + 'static,
{
    let session = init_model(params.model_path.clone(), params.try_with_cuda)?;
    if params.config_data == "sense-voice_onnx" {
        sense_voice::launch_caption(session, params, result_callback).await?
    } else {
        Err(anyhow::anyhow!(
            "Unsupported model configuration: {}",
            params.config_data
        ))?;
    }
    Ok(())
}

pub fn init_model(model_path: String, try_gpu: bool) -> anyhow::Result<Session> {
    let session = Session::builder()?
        .with_execution_providers(if try_gpu {
            get_onnx_execution_providers()
        } else {
            Vec::new()
        })?
        .commit_from_file(model_path)?;
    for ele in session.inputs.iter().clone() {
        println!("ONNX model Input: {:?}", ele);
    }
    Ok(session)
}

fn get_onnx_execution_providers() -> Vec<ExecutionProviderDispatch> {
    let mut providers = Vec::new();
    #[cfg(target_os = "macos")]
    providers.push(CoreMLExecutionProvider::default().build());
    #[cfg(any(target_os = "linux", target_os = "windows"))]
    {
        providers.push(TensorRTExecutionProvider::default().build());
        providers.push(CUDAExecutionProvider::default().build());
        providers.push(WebGPUExecutionProvider::default().build());
    }
    #[cfg(target_os = "windows")]
    providers.push(DirectMLExecutionProvider::default().build());
    providers
}

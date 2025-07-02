use ort::execution_providers::{
    ExecutionProvider, WebGPUExecutionProvider, XNNPACKExecutionProvider,
};
use ort::session::Session;

mod sense_voice;

#[cfg(target_os = "macos")]
use ort::execution_providers::CoreMLExecutionProvider;

#[cfg(any(target_os = "linux", target_os = "windows"))]
use ort::execution_providers::CUDAExecutionProvider;

use crate::whisper_caption::{whisper::Segment, LaunchCaptionParams};
#[cfg(target_os = "windows")]
use ort::execution_providers::DirectMLExecutionProvider;
use ort::session::builder::SessionBuilder;

pub async fn launch_caption<F>(
    params: LaunchCaptionParams,
    result_callback: F,
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
    let mut session_builder = Session::builder()?;
    _register_execution_providers(&mut session_builder, try_gpu)?;
    Ok(session_builder.commit_from_file(model_path)?)
}

fn _register_execution_providers(
    buillder: &mut SessionBuilder,
    try_gpu: bool,
) -> anyhow::Result<()> {
    let mut is_gpu_available = false;
    let mut is_dml_available = false;
    if try_gpu {
        #[cfg(target_os = "macos")]
        {
            let core_ml = CoreMLExecutionProvider::default();
            if core_ml.register(buillder).is_ok() {
                println!("Registered CoreML execution provider");
            }
        }

        #[cfg(any(target_os = "linux", target_os = "windows"))]
        {
            let cuda = CUDAExecutionProvider::default();
            if cuda.register(buillder).is_ok() {
                is_gpu_available = true;
                println!("Registered CUDA execution provider");
            } else {
                eprintln!("Failed to register CUDA execution provider");
            }

            let w_gpu = WebGPUExecutionProvider::default();
            if w_gpu.register(buillder).is_ok() {
                is_gpu_available = true;
                println!("Registered WebGPU execution provider");
            } else {
                eprintln!("Failed to register WebGPU execution provider");
            }
        }

        // or else, use Dml
        #[cfg(target_os = "windows")]
        {
            if !is_gpu_available {
                let direct_ml = DirectMLExecutionProvider::default();
                if direct_ml.register(buillder).is_ok() {
                    is_dml_available = true;
                    println!("Registered DirectML execution provider");
                } else {
                    eprintln!("Failed to register DirectML execution provider");
                }
            }
        }
    }

    // if you use dml, any other execution provider is not needed
    if !is_dml_available {
        let xnn_pack = XNNPACKExecutionProvider::default();
        if xnn_pack.register(buillder).is_ok() {
            println!("Registered XNNPACK execution provider");
        } else {
            eprintln!("Failed to register XNNPACK execution provider");
        }
    }

    Ok(())
}

use ort::execution_providers::{ExecutionProvider, XNNPACKExecutionProvider};
use ort::session::Session;

pub mod sense_voice;
pub mod vad;
pub mod whisper;

#[cfg(target_os = "macos")]
use ort::execution_providers::CoreMLExecutionProvider;

#[cfg(any(target_os = "linux", target_os = "windows"))]
use ort::execution_providers::CUDAExecutionProvider;

#[cfg(target_os = "windows")]
use ort::execution_providers::DirectMLExecutionProvider;
use ort::session::builder::SessionBuilder;

use crate::candle_models::whisper::model::Segment;
use crate::candle_models::whisper::LaunchCaptionParams;

pub async fn launch_caption<F>(
    params: LaunchCaptionParams,
    result_callback: F,
) -> anyhow::Result<()>
where
    F: FnMut(Vec<Segment>) + Send + 'static,
{
    if params.config_data == "sense-voice_onnx" {
        let model_path: String = params.models.values().next().unwrap().to_string();
        let session = init_model(model_path, params.try_with_cuda)?;
        sense_voice::launch_caption(session, params, result_callback).await?
    } else if params.config_data == "whisper_onnx" {
        let encoder_model_path: String =
            params.models.get("encoder.int8.onnx").unwrap().to_string();
        let decoder_model_path: String =
            params.models.get("decoder.int8.onnx").unwrap().to_string();

        let encoder_session = init_model(encoder_model_path, params.try_with_cuda)?;
        let decoder_session = init_model(decoder_model_path, params.try_with_cuda)?;

        whisper::launch_caption(encoder_session, decoder_session, params, result_callback).await?
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
    register_execution_providers(&mut session_builder, try_gpu, model_path.clone())?;
    Ok(session_builder.commit_from_file(model_path)?)
}

pub fn register_execution_providers(
    builder: &mut SessionBuilder,
    try_gpu: bool,
    model_print_name: String,
) -> anyhow::Result<()> {
    #[allow(unused_variables)]
    #[allow(unused_mut)]
    let mut is_gpu_available = false;
    #[allow(unused_variables)]
    #[allow(unused_mut)]
    let mut is_dml_available = false;
    if try_gpu {
        #[cfg(target_os = "macos")]
        {
            let core_ml = CoreMLExecutionProvider::default();
            if core_ml.register(builder).is_ok() {
                println!(
                    "[{}] Registered CoreML execution provider",
                    model_print_name
                );
            }
        }

        #[cfg(any(target_os = "linux", target_os = "windows"))]
        {
            let cuda = CUDAExecutionProvider::default();
            if cuda.register(builder).is_ok() {
                is_gpu_available = true;
                println!("[{}] Registered CUDA execution provider", model_print_name);
            } else {
                eprintln!(
                    "[{}] Failed to register CUDA execution provider",
                    model_print_name
                );
            }

            let w_gpu = WebGPUExecutionProvider::default();
            if w_gpu.register(builder).is_ok() {
                is_gpu_available = true;
                println!(
                    "[{}] Registered WebGPU execution provider",
                    model_print_name
                );
            } else {
                eprintln!(
                    "[{}] Failed to register WebGPU execution provider",
                    model_print_name
                );
            }
        }

        // or else, use Dml
        #[cfg(target_os = "windows")]
        {
            if !is_gpu_available {
                let direct_ml = DirectMLExecutionProvider::default();
                if direct_ml.register(builder).is_ok() {
                    is_dml_available = true;
                    println!(
                        "[{}] Registered DirectML execution provider",
                        model_print_names
                    );
                } else {
                    eprintln!(
                        "[{}] Failed to register DirectML execution provider",
                        model_print_name
                    );
                }
            }
        }
    }

    // if you use dml, any other execution provider is not needed
    if !is_dml_available {
        let xnn_pack = XNNPACKExecutionProvider::default();
        if xnn_pack.register(builder).is_ok() {
            println!(
                "[{}] Registered XNNPACK execution provider",
                model_print_name
            );
        } else {
            eprintln!(
                "[{}] Failed to register XNNPACK execution provider",
                model_print_name
            );
        }
    }

    Ok(())
}

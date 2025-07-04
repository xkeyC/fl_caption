use ort::execution_providers::{ExecutionProvider, XNNPACKExecutionProvider};
use ort::session::Session;
use std::collections::HashMap;

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
    if params.model_type == "sense-voice_onnx" {
        sense_voice::launch_caption(params, result_callback).await?
    } else if params.model_type == "whisper_onnx" {
        whisper::launch_caption(params, result_callback).await?
    } else {
        Err(anyhow::anyhow!(
            "Unsupported model configuration: {}",
            params.model_type
        ))?
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
            use ort::execution_providers::coreml::CoreMLComputeUnits;
            let mut core_ml = CoreMLExecutionProvider::default();
            core_ml = core_ml.with_compute_units(CoreMLComputeUnits::All);
            if core_ml.register(builder).is_ok() {
                println!(
                    "[{}] Registered CoreML execution provider",
                    model_print_name
                );
            }else {
                eprintln!(
                    "[{}] Failed to register CoreML execution provider",
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
                        model_print_name
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

pub fn find_model_path(
    model_map: &HashMap<String, String>,
    keyword: Option<&str>,
) -> Option<String> {
    for (key, path) in model_map {
        let keyword_match = match keyword {
            Some(kw) => key.contains(kw),
            None => true,
        };
        if keyword_match && path.ends_with(".onnx") {
            return Some(path.clone());
        }
    }
    None
}

use ort::execution_providers::{ExecutionProvider, XNNPACKExecutionProvider};
use ort::session::Session;
use std::collections::HashMap;

pub mod sense_voice;
pub mod vad;
pub mod whisper;

#[cfg(target_os = "macos")]
use ort::execution_providers::CoreMLExecutionProvider;

#[cfg(any(target_os = "linux", target_os = "windows"))]
use ort::execution_providers::{
    cuda::CUDAAttentionBackend, CUDAExecutionProvider, TensorRTExecutionProvider,
};

#[cfg(target_os = "windows")]
use ort::execution_providers::DirectMLExecutionProvider;

use ort::session::builder::{GraphOptimizationLevel, SessionBuilder};

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
        // https://github.com/k2-fsa/sherpa-onnx/tree/master/scripts/sense-voice
        sense_voice::launch_caption(params, result_callback).await?
    } else if params.model_type == "whisper-olive_onnx" {
        // https://github.com/microsoft/Olive/tree/d4d424f9b370e736e79b17487c037d5aad766315/examples/whisper
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
    session_builder = session_builder.with_optimization_level(GraphOptimizationLevel::Level3)?;
    session_builder = session_builder.with_intra_threads(4)?;
    session_builder = register_operator_library(session_builder)?;
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
            } else {
                eprintln!(
                    "[{}] Failed to register CoreML execution provider",
                    model_print_name
                );
            }
        }

        #[cfg(any(target_os = "linux", target_os = "windows"))]
        {
            let tensor_rt = TensorRTExecutionProvider::default();
            if tensor_rt.register(builder).is_ok() {
                println!(
                    "[{}] Registered TensorRT execution provider",
                    model_print_name
                );
            } else {
                eprintln!(
                    "[{}] Failed to register TensorRT execution provider",
                    model_print_name
                );
            }

            let mut cuda = CUDAExecutionProvider::default();
            cuda = cuda
                .with_attention_backend(CUDAAttentionBackend::all())
                .with_skip_layer_norm_strict_mode(true)
                .with_prefer_nhwc(true);
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

fn register_operator_library(builder: SessionBuilder) -> anyhow::Result<SessionBuilder> {
    #[cfg(target_os = "windows")]
    let lib_name = "ortextensions.dll";

    #[cfg(target_os = "linux")]
    let lib_name = "libortextensions.so";

    #[cfg(target_os = "macos")]
    let lib_name = "libortextensions.dylib";

    // Try to find the library in the current directory or a standard location
    let lib_path = std::env::current_exe()
        .ok()
        .and_then(|exe_path| exe_path.parent().map(|p| p.join(lib_name)))
        .unwrap_or_else(|| std::path::PathBuf::from(lib_name));

    if lib_path.exists() {
        println!("Registering operator library: {}", lib_path.display());
        Ok(builder.with_operator_library(lib_path)?)
    } else {
        println!(
            "Operator library not found at: {}, proceeding without it",
            lib_path.display()
        );
        Ok(builder)
    }
}

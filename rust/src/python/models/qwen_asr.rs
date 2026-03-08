use pyo3::prelude::*;
use pyo3::types::{PyDict, PyList};

use crate::python::setup::setup_python_path;
use crate::python::types::TranscriptionResult;

pub fn init_qwen_asr(
    model_path: Option<String>,
    forced_aligner_path: Option<String>,
    device: Option<String>,
    dtype: Option<String>,
    max_inference_batch_size: Option<i32>,
    max_new_tokens: Option<i32>,
) -> PyResult<bool> {
    println!("[init_qwen_asr] Starting Python initialization...");
    Python::attach(|py| {
        println!("[init_qwen_asr] Setting up Python path...");
        setup_python_path(py)?;

        println!("[init_qwen_asr] Importing asr_wrapper module...");
        let qwen_module = py.import("asr_wrapper")?;
        let init_func = qwen_module.getattr("init_model")?;

        println!("[init_qwen_asr] Calling init_model...");
        let kwargs = PyDict::new(py);
        if let Some(path) = model_path {
            kwargs.set_item("model_path", path)?;
        }
        if let Some(path) = forced_aligner_path {
            kwargs.set_item("forced_aligner_path", path)?;
        }
        if let Some(dev) = device {
            kwargs.set_item("device", dev)?;
        }
        if let Some(dt) = dtype {
            kwargs.set_item("dtype", dt)?;
        }
        if let Some(batch_size) = max_inference_batch_size {
            kwargs.set_item("max_inference_batch_size", batch_size)?;
        }
        if let Some(tokens) = max_new_tokens {
            kwargs.set_item("max_new_tokens", tokens)?;
        }

        let result: bool = init_func.call((), Some(&kwargs))?.extract()?;
        println!("[init_qwen_asr] init_model returned: {}", result);
        Ok(result)
    })
}

pub fn is_qwen_model_loaded() -> PyResult<bool> {
    Python::attach(|py| {
        setup_python_path(py)?;
        let qwen_module = py.import("asr_wrapper")?;
        let func = qwen_module.getattr("is_model_loaded")?;
        let result: bool = func.call0()?.extract()?;
        Ok(result)
    })
}

pub fn transcribe_audio(
    audio: String,
    language: Option<String>,
    context: Option<String>,
    return_time_stamps: bool,
) -> PyResult<TranscriptionResult> {
    Python::attach(|py| {
        setup_python_path(py)?;

        let qwen_module = py.import("asr_wrapper")?;
        let transcribe_func = qwen_module.getattr("transcribe")?;

        let kwargs = PyDict::new(py);
        kwargs.set_item("audio", &audio)?;
        if let Some(lang) = &language {
            kwargs.set_item("language", lang)?;
        }
        if let Some(ctx) = &context {
            kwargs.set_item("context", ctx)?;
        }
        kwargs.set_item("return_time_stamps", return_time_stamps)?;

        let result = transcribe_func.call((), Some(&kwargs))?;
        extract_transcription_result(py, &result)
    })
}

pub fn transcribe_from_samples(
    samples: Vec<f32>,
    sample_rate: u32,
    language: Option<String>,
    context: Option<String>,
    return_time_stamps: bool,
) -> PyResult<TranscriptionResult> {
    Python::attach(|py| {
        setup_python_path(py)?;

        let qwen_module = py.import("asr_wrapper")?;
        let transcribe_func = qwen_module.getattr("transcribe_from_samples")?;

        let kwargs = PyDict::new(py);
        kwargs.set_item("samples", samples)?;
        kwargs.set_item("sample_rate", sample_rate)?;
        if let Some(lang) = &language {
            kwargs.set_item("language", lang)?;
        }
        if let Some(ctx) = &context {
            kwargs.set_item("context", ctx)?;
        }
        kwargs.set_item("return_time_stamps", return_time_stamps)?;

        let result = transcribe_func.call((), Some(&kwargs))?;
        extract_transcription_result(py, &result)
    })
}

pub fn transcribe_batch(
    audio_list: Vec<String>,
    language_list: Option<Vec<Option<String>>>,
    context_list: Option<Vec<String>>,
    return_time_stamps: bool,
) -> PyResult<Vec<TranscriptionResult>> {
    Python::attach(|py| {
        setup_python_path(py)?;

        let qwen_module = py.import("asr_wrapper")?;
        let transcribe_func = qwen_module.getattr("transcribe_batch")?;

        let kwargs = PyDict::new(py);
        kwargs.set_item("audio_list", audio_list)?;
        if let Some(languages) = language_list {
            kwargs.set_item("language_list", languages)?;
        }
        if let Some(contexts) = context_list {
            kwargs.set_item("context_list", contexts)?;
        }
        kwargs.set_item("return_time_stamps", return_time_stamps)?;

        let result = transcribe_func.call((), Some(&kwargs))?;
        let list = result.cast::<PyList>()?;

        let mut results = Vec::new();
        for item in list.iter() {
            results.push(extract_transcription_result(py, &item)?);
        }
        Ok(results)
    })
}

fn extract_transcription_result(
    _py: Python<'_>,
    result: &Bound<'_, PyAny>,
) -> PyResult<TranscriptionResult> {
    let dict = result.cast::<PyDict>()?;

    let error: Option<String> = dict
        .get_item("error")?
        .map(|v| v.extract())
        .transpose()?
        .flatten();

    if let Some(err) = error {
        return Ok(TranscriptionResult {
            language: String::new(),
            text: String::new(),
            time_stamps: vec![],
            error: Some(err),
        });
    }

    let language: String = dict
        .get_item("language")?
        .map(|v| v.extract())
        .transpose()?
        .unwrap_or_default();

    let text: String = dict
        .get_item("text")?
        .map(|v| v.extract())
        .transpose()?
        .unwrap_or_default();

    let mut time_stamps = Vec::new();
    if let Some(ts_list) = dict.get_item("time_stamps")? {
        let ts_list = ts_list.cast::<PyList>()?;
        for ts in ts_list.iter() {
            let ts_dict = ts.cast::<PyDict>()?;
            time_stamps.push(crate::python::types::TimeStamp {
                text: ts_dict
                    .get_item("text")?
                    .map(|v| v.extract())
                    .transpose()?
                    .unwrap_or_default(),
                start_time: ts_dict
                    .get_item("start_time")?
                    .map(|v| v.extract())
                    .transpose()?
                    .unwrap_or(0.0),
                end_time: ts_dict
                    .get_item("end_time")?
                    .map(|v| v.extract())
                    .transpose()?
                    .unwrap_or(0.0),
            });
        }
    }

    Ok(TranscriptionResult {
        language,
        text,
        time_stamps,
        error: None,
    })
}

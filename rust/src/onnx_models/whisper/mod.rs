pub mod model;
pub mod multilingual;

use crate::candle_models::whisper::{
    model::{DecodingResult, Segment, WhisperStatus},
    LaunchCaptionParams,
};
use crate::onnx_models::whisper::model::WhisperModel;

pub async fn launch_caption<F>(
    params: LaunchCaptionParams,
    mut result_callback: F,
) -> anyhow::Result<()>
where
    F: FnMut(Vec<Segment>) + Send + 'static,
{
    use crate::audio_capture::{AudioCapture, AudioCaptureConfig, PlatformAudioCapture};
    use crate::onnx_models::vad;
    use std::time::Duration;
    use tokio::time::Instant;

    let LaunchCaptionParams {
        models,
        audio_device,
        audio_device_is_input,
        audio_language,
        cancel_token,
        inference_interval_ms,
        vad_model_path,
        vad_filters_value,
        whisper_max_audio_duration,
        ..
    } = params;

    let model_path = super::find_model_path(&models, None).unwrap();
    let session = super::init_model(model_path, params.try_with_cuda)?;

    // 初始化Whisper模型
    result_callback(_make_status_response(WhisperStatus::Loading));
    let mut model = WhisperModel::from_session(session)?;

    // 设置音频捕获配置
    let audio_capture_config = AudioCaptureConfig {
        device: audio_device,
        is_input: audio_device_is_input.unwrap_or(true),
        target_sample_rate: 16000,
        target_channels: 1,
    };

    let audio_capture = PlatformAudioCapture::new(audio_capture_config)?;
    let audio_info = audio_capture.get_info();
    println!("Whisper Audio capture info: {:?}", audio_info);

    // 开始音频捕获
    let rx = audio_capture.start_capture(cancel_token.child_token())?;

    result_callback(_make_status_response(WhisperStatus::Ready));
    println!("Whisper Ready...");

    // 初始化音频处理状态
    let mut buffered_pcm = vec![];
    let mut history_pcm = Vec::new();
    let mut last_inference_time = Instant::now();
    let mut first_inference_done = false;
    let inference_interval = Duration::from_millis(inference_interval_ms.unwrap_or(2000)); // 默认2000毫秒
    let max_audio_duration: usize = whisper_max_audio_duration.unwrap_or(12) as usize; // 默认12秒
    let language = audio_language.as_deref(); // Whisper语言设置

    println!("Check and loading VAD model...");
    let mut vad_model = if let Some(vad_model_path) = vad_model_path {
        let model = vad::new_vad_model(vad_model_path, false);
        if let Ok(model) = model {
            Some(model)
        } else {
            println!("Failed to load VAD model: {:?}", model.err().unwrap());
            None
        }
    } else {
        None
    };

    // 音频处理主循环
    println!("Starting Whisper audio processing loop...");
    let mut debug_counter = 0;

    while !cancel_token.is_cancelled() {
        debug_counter += 1;
        if debug_counter % 500 == 0 {
            println!(
                "Whisper audio processing loop iteration {}, buffered_pcm.len(): {}",
                debug_counter,
                buffered_pcm.len()
            );
        }

        // 接收音频数据
        let pcm = rx.recv_timeout(Duration::from_millis(100));

        if pcm.is_err() {
            let err = pcm.unwrap_err();
            if debug_counter % 1000 == 0 {
                println!(
                    "Audio recv timeout or error: {:?}, cancel_token cancelled: {}",
                    err,
                    cancel_token.is_cancelled()
                );
            }
            if cancel_token.is_cancelled() {
                break;
            }
            continue;
        }

        let pcm = pcm.unwrap();

        static mut AUDIO_RECEIVED: bool = false;
        unsafe {
            if !AUDIO_RECEIVED {
                println!("Whisper first audio data received: {} samples", pcm.len());
                AUDIO_RECEIVED = true;
            } else if pcm.len() > 0 && debug_counter % 100 == 0 {
                println!(
                    "Whisper audio data: {} samples (debug every 100 iterations)",
                    pcm.len()
                );
            }
        }

        buffered_pcm.extend_from_slice(&pcm);

        if buffered_pcm.len() > 0 && (buffered_pcm.len() % 16000 == 0 || debug_counter % 200 == 0) {
            println!(
                "Total buffered_pcm length: {} samples ({:.1}s)",
                buffered_pcm.len(),
                buffered_pcm.len() as f32 / 16000.0
            );
        }

        // 首次启动时，等待3秒数据
        if !first_inference_done {
            if buffered_pcm.len() < 3 * 16000 {
                continue;
            }
            first_inference_done = true;
        }

        // 检查推理间隔
        let now = Instant::now();
        if now.duration_since(last_inference_time) < inference_interval {
            continue;
        }

        // 记录推理开始时间
        let inference_start = Instant::now();

        // VAD检测
        if let Some(vad_model) = vad_model.as_mut() {
            let resampled_pcm = buffered_pcm.clone();
            let vad_result = vad_model.check_vad(resampled_pcm, vad_filters_value);
            if vad_result.is_err() {
                println!("VAD error: {:?}", vad_result.err().unwrap());
            } else {
                let vad_result = vad_result?;
                println!(
                    "Whisper VAD prediction: {:?} filtered_count: {:?}",
                    vad_result.prediction, vad_result.filtered_count
                );
                if vad_result.prediction > vad_filters_value.unwrap_or(0.1) {
                    buffered_pcm = vad_result.pcm_results;
                } else {
                    buffered_pcm.clear();
                    last_inference_time = Instant::now();
                    continue;
                }
            }
        }

        // 音频长度管理
        let max_samples = max_audio_duration * 16000;
        let total_len = history_pcm.len() + buffered_pcm.len();

        let mut adjusted_history_pcm = history_pcm.clone();
        if total_len > max_samples {
            let excess = total_len - max_samples;
            println!(
                "Whisper history_pcm len: {} buffered_pcm len: {} excess: {}",
                history_pcm.len(),
                buffered_pcm.len(),
                excess
            );
            if history_pcm.len() > excess {
                adjusted_history_pcm = history_pcm[excess..].to_vec();
            } else {
                adjusted_history_pcm = Vec::new();
            }
        }

        // 合并音频数据
        let mut combined_pcm = Vec::with_capacity(adjusted_history_pcm.len() + buffered_pcm.len());
        combined_pcm.extend_from_slice(&adjusted_history_pcm);
        combined_pcm.extend_from_slice(&buffered_pcm);

        history_pcm = combined_pcm.clone();
        buffered_pcm.clear();

        let pcm = combined_pcm;

        // Whisper推理
        match model.inference(&pcm, language, Some("transcribe")) {
            Ok(text) => {
                let inference_duration = inference_start.elapsed();

                // 创建结果段
                let segment = model::create_whisper_segment(
                    text,
                    pcm.len() as f64 / 16000.0, // 音频时长（秒）
                    inference_duration.as_millis(),
                    language.map(|s| s.to_string()),
                );

                result_callback(vec![segment]);
            }
            Err(e) => {
                println!("Whisper inference error: {:?}", e);
                // 发送错误状态
                result_callback(_make_status_response(WhisperStatus::Error));
            }
        }

        last_inference_time = now;
    }

    println!("Whisper transcription cancelled");
    result_callback(_make_status_response(WhisperStatus::Exit));
    println!("Whisper Exit");
    Ok(())
}

fn _make_status_response(status: WhisperStatus) -> Vec<Segment> {
    vec![Segment {
        start: 0.0,
        duration: 0.0,
        dr: DecodingResult {
            tokens: vec![],
            text: "".to_string(),
            avg_logprob: 0.0,
            no_speech_prob: 0.0,
            temperature: 0.0,
            compression_ratio: 0.0,
        },
        reasoning_duration: None,
        reasoning_lang: None,
        audio_duration: None,
        status,
    }]
}

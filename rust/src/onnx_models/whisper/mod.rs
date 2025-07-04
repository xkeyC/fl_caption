pub mod model;

use crate::audio_capture::{AudioCapture, AudioCaptureConfig, PlatformAudioCapture};
use crate::candle_models::whisper::{model::Segment, LaunchCaptionParams};
use candle_transformers::models::whisper::Config;
use model::ORTModelForWhisper;
use std::time::Duration;
use tokenizers::Tokenizer;
use tokio::time::Instant;

pub async fn launch_caption<F>(
    params: LaunchCaptionParams,
    mut result_callback: F,
) -> anyhow::Result<()>
where
    F: FnMut(Vec<Segment>) + Send + 'static,
{
    let LaunchCaptionParams {
        models,
        config_data,
        tokenizer_data,
        audio_device,
        audio_device_is_input,
        cancel_token,
        try_with_cuda,
        inference_interval_ms,
        whisper_max_audio_duration,
        whisper_temperature,
        ..
    } = params;

    // 创建tokenizer
    let tokenizer = Tokenizer::from_bytes(tokenizer_data)
        .map_err(|e| anyhow::anyhow!("Failed to create tokenizer: {}", e))?;

    // 从config_data解析配置
    let config: Config = serde_json::from_str(&config_data)
        .map_err(|e| anyhow::anyhow!("Failed to parse config: {}", e))?;

    // 初始化ONNX Whisper模型
    let mut whisper_model = ORTModelForWhisper::new(&models, tokenizer, config, try_with_cuda,None)
        .map_err(|e| anyhow::anyhow!("Failed to initialize ONNX Whisper model: {}", e))?;

    // 设置音频捕获配置
    let audio_capture_config = AudioCaptureConfig {
        device: audio_device,
        is_input: audio_device_is_input.unwrap_or(true),
        target_sample_rate: 16000,
        target_channels: 1,
    };

    let audio_capture = PlatformAudioCapture::new(audio_capture_config)?;
    let audio_info = audio_capture.get_info();
    println!("Audio capture info: {:?}", audio_info);

    // 启动音频捕获
    let rx = audio_capture.start_capture(cancel_token.child_token())?;

    // 发送就绪状态
    result_callback(vec![Segment {
        start: 0.0,
        duration: 0.0,
        dr: crate::candle_models::whisper::model::DecodingResult {
            tokens: vec![],
            text: "ONNX Whisper model ready".to_string(),
            avg_logprob: 0.0,
            no_speech_prob: 0.0,
            temperature: 0.0,
            compression_ratio: 0.0,
        },
        reasoning_duration: None,
        reasoning_lang: None,
        audio_duration: None,
        status: crate::candle_models::whisper::model::WhisperStatus::Ready,
    }]);

    // 音频处理参数
    let inference_interval = Duration::from_millis(inference_interval_ms.unwrap_or(2000));
    let max_audio_duration = whisper_max_audio_duration.unwrap_or(12) as usize;
    let temperature = whisper_temperature.unwrap_or(0.0);

    let mut buffered_pcm = Vec::new();
    let mut history_pcm = Vec::new();
    let mut last_inference_time = Instant::now();

    println!("Starting ONNX Whisper audio processing loop...");

    // 主音频处理循环
    while !cancel_token.is_cancelled() {
        // 接收音频数据
        let pcm_result = rx.recv_timeout(Duration::from_millis(100));

        if pcm_result.is_err() {
            if cancel_token.is_cancelled() {
                break;
            }
            continue;
        }

        let pcm = pcm_result.unwrap();
        buffered_pcm.extend_from_slice(&pcm);

        // 检查推理间隔
        let now = Instant::now();
        if now.duration_since(last_inference_time) < inference_interval {
            continue;
        }

        // 准备推理数据
        let max_samples = max_audio_duration * 16000;
        let total_len = history_pcm.len() + buffered_pcm.len();

        let inference_pcm = if total_len > max_samples {
            // 截取最新的音频数据
            let excess = total_len - max_samples;
            if excess >= history_pcm.len() {
                // 如果超出部分大于等于历史音频，只使用缓冲音频的一部分
                let start_idx = excess - history_pcm.len();
                buffered_pcm[start_idx..].to_vec()
            } else {
                // 使用部分历史音频和全部缓冲音频
                let mut combined = history_pcm[excess..].to_vec();
                combined.extend_from_slice(&buffered_pcm);
                combined
            }
        } else {
            // 组合历史和当前音频
            let mut combined = history_pcm.clone();
            combined.extend_from_slice(&buffered_pcm);
            combined
        };

        // 确保有足够的音频数据
        if inference_pcm.len() < 16000 {
            // 至少1秒音频
            continue;
        }

        // 执行推理
        let inference_start = Instant::now();
        match whisper_model.transcribe_audio(&inference_pcm, 16000, Some(256), Some(temperature)) {
            Ok(text) => {
                let inference_duration = inference_start.elapsed();
                let audio_duration = (inference_pcm.len() as f32 / 16000.0 * 1000.0) as u128;

                // 如果有有效文本，发送结果
                if !text.trim().is_empty() {
                    let segment = Segment {
                        start: 0.0, // 可以根据需要计算实际时间戳
                        duration: audio_duration as f64 / 1000.0,
                        dr: crate::candle_models::whisper::model::DecodingResult {
                            tokens: vec![], // 如果需要可以保存token
                            text,
                            avg_logprob: 0.0,
                            no_speech_prob: 0.0,
                            temperature: temperature as f64,
                            compression_ratio: 0.0,
                        },
                        reasoning_duration: Some(inference_duration.as_millis()),
                        reasoning_lang: Some("auto".to_string()),
                        audio_duration: Some(audio_duration),
                        status: crate::candle_models::whisper::model::WhisperStatus::Working,
                    };

                    result_callback(vec![segment]);
                }
            }
            Err(e) => {
                println!("ONNX Whisper inference error: {}", e);
            }
        }

        // 更新历史音频和重置缓冲区
        history_pcm = inference_pcm;
        buffered_pcm.clear();
        last_inference_time = now;
    }

    println!("ONNX Whisper processing loop ended");
    Ok(())
}

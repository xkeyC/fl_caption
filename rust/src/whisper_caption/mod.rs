use std::time::Duration;
use whisper_rs::{WhisperContext, FullParams, SamplingStrategy};
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use native_dialog::{MessageDialog, MessageType};
use std::sync::mpsc as std_mpsc;
use std::{panic, thread};
use tokio::sync::mpsc;
use tokio::time::Instant;
use tokio_util::sync::CancellationToken;

pub async fn launch_caption<F>(
    whisper_model: WhisperContext,
    whisper_state: whisper_rs::WhisperState,
    audio_device: Option<String>,
    audio_device_is_input: Option<bool>,
    audio_language: Option<String>,
    cancel_token: CancellationToken,
    with_timestamps: Option<bool>,
    verbose: Option<bool>,
    try_with_cuda: bool,
    inference_timeout: Option<Duration>,   // 推理总超时参数
    max_tokens_per_segment: Option<usize>, // 防止幻觉的每段最大token数
    mut result_callback: F,
) -> anyhow::Result<()>
where
    F: FnMut(Vec<whisper_rs::Segment>) + Send + 'static,
{
    result_callback(_make_status_response(whisper_rs::WhisperStatus::Loading));

    let arg_language = audio_language;
    let arg_device = audio_device;
    let is_input = audio_device_is_input.unwrap_or(true);

    // Set up the audio device and stream
    let host = cpal::default_host();

    let audio_device = if is_input {
        match arg_device {
            None => host.default_input_device(),
            Some(device) => host
                .input_devices()?
                .find(|x| x.name().map_or(false, |y| y == device)),
        }
    } else {
        match arg_device {
            None => host.default_output_device(),
            Some(device) => host
                .output_devices()?
                .find(|x| x.name().map_or(false, |y| y == device)),
        }
    }
    .expect("failed to find the audio device");

    let audio_config = if is_input {
        audio_device
            .default_input_config()
            .expect("Failed to get default input config")
    } else {
        audio_device
            .default_output_config()
            .expect("Failed to get default output config")
    };

    let device_name = audio_device.name()?;

    println!("audio device -> {device_name:?} config -> {audio_config:?}");

    let channel_count = audio_config.channels() as usize;
    let in_sample_rate = audio_config.sample_rate().0 as usize;
    let resample_ratio = 16000. / in_sample_rate as f64;

    // 使用标准库通道来处理音频输入流和处理线程间的通信
    let (tx, rx) = std_mpsc::channel::<Vec<f32>>();

    let audio_cancel_token = cancel_token.child_token();
    let processor_cancel_token = cancel_token.child_token();

    // 启动一个线程来处理音频输入
    let audio_thread = thread::spawn(move || {
        let audio_cancel_token_clone = audio_cancel_token.child_token();
        // 在标准线程中创建并管理音频流
        let stream = if cfg!(target_os = "macos") && !is_input {
            match audio_device.build_output_stream(
                &audio_config.config(),
                move |pcm: &mut [f32], _: &cpal::OutputCallbackInfo| {
                    if audio_cancel_token.is_cancelled() {
                        return;
                    }
                    let captured_pcm = pcm
                        .iter()
                        .step_by(channel_count)
                        .copied()
                        .collect::<Vec<f32>>();

                    if !captured_pcm.is_empty() {
                        // 使用 send 发送音频数据
                        let _ = tx.send(captured_pcm);
                    }
                },
                move |err| {
                    eprintln!("an error occurred on stream: {}", err);
                },
                None,
            ) {
                Ok(s) => s,
                Err(e) => {
                    eprintln!("Failed to create audio stream: {}", e);
                    return;
                }
            }
        } else {
            match audio_device.build_input_stream(
                &audio_config.config(),
                move |pcm: &[f32], _: &cpal::InputCallbackInfo| {
                    if audio_cancel_token.is_cancelled() {
                        return;
                    }

                    let pcm = pcm
                        .iter()
                        .step_by(channel_count)
                        .copied()
                        .collect::<Vec<f32>>();

                    if !pcm.is_empty() {
                        // 使用 send 发送音频数据
                        let _ = tx.send(pcm);
                    }
                },
                move |err| {
                    eprintln!("an error occurred on stream: {}", err);
                },
                None,
            ) {
                Ok(s) => s,
                Err(e) => {
                    eprintln!("Failed to create audio stream: {}", e);
                    return;
                }
            }
        };

        stream.play().unwrap_or_else(|e| {
            eprintln!("Failed to start audio stream: {}", e);
        });

        // 使用取消令牌等待取消信号
        while !audio_cancel_token_clone.is_cancelled() {
            thread::sleep(Duration::from_millis(100));
        }

        // 确保流被正确停止
        drop(stream);
        println!("Audio stream stopped");
    });

    // 使用 tokio 通道用于处理推理结果
    let (result_tx, mut result_rx) = mpsc::channel::<Vec<f32>>(100);

    // 创建处理音频数据的 tokio 任务
    let processor_task = tokio::spawn(async move {
        // 使用 rubato 进行重采样
        use rubato::Resampler;
        let mut resampler: rubato::FastFixedIn<f32> = rubato::FastFixedIn::<f32>::new(
            resample_ratio,
            10.,
            rubato::PolynomialDegree::Septic,
            1024,
            1,
        )
        .unwrap();

        while let Ok(pcm) = rx.recv() {
            if processor_cancel_token.is_cancelled() {
                break;
            }

            // 立即对音频数据进行重采样
            let mut resampled_pcm = vec![];
            let full_chunks = pcm.len() / 1024;

            // 处理完整的1024样本块
            for chunk in 0..full_chunks {
                let pcm_chunk = &pcm[chunk * 1024..(chunk + 1) * 1024];
                if let Ok(res) = resampler.process(&[&pcm_chunk], None) {
                    resampled_pcm.extend_from_slice(&res[0]);
                }
            }

            // 如果有剩余不足1024的样本，也进行处理
            let remaining = pcm.len() % 1024;
            if remaining > 0 {
                let start = full_chunks * 1024;
                let mut last_chunk = vec![0.0f32; 1024];
                last_chunk[..remaining].copy_from_slice(&pcm[start..]);

                if let Ok(res) = resampler.process(&[&last_chunk], None) {
                    // 只添加有效的重采样数据
                    let valid_len = (remaining as f64 * resample_ratio).ceil() as usize;
                    resampled_pcm.extend_from_slice(&res[0][..valid_len.min(res[0].len())]);
                }
            }

            let _ = result_tx.send(resampled_pcm).await;
        }
    });

    result_callback(_make_status_response(whisper_rs::WhisperStatus::Ready));
    println!("Whisper Ready...");

    // 处理任务在当前函数中运行
    let mut buffered_pcm = vec![];
    let mut history_pcm = Vec::new();
    let mut last_inference_time = Instant::now();
    let mut first_inference_done = false;
    let inference_interval = Duration::from_millis(2000); // 推理间隔时间
    let max_audio_duration: usize = 12; // 最大音频时长，单位：秒
    let mut language_token_set = false;
    let mut language_token_name: Option<String> = None;

    // 处理循环
    while !cancel_token.is_cancelled() {
        // 尝试接收音频数据，设置超时以便定期检查取消状态
        let pcm = tokio::time::timeout(Duration::from_millis(100), result_rx.recv()).await;

        // 如果接收超时或通道关闭，检查是否应该取消
        if pcm.is_err() || pcm.as_ref().unwrap().is_none() {
            if cancel_token.is_cancelled() {
                break;
            }
            continue;
        }

        // 处理接收到的音频数据
        let pcm = pcm.unwrap().unwrap();

        buffered_pcm.extend_from_slice(&pcm);

        // 首次启动时，等待3秒数据
        if !first_inference_done {
            if buffered_pcm.len() < 3 * 16000 {
                continue;
            }
            first_inference_done = true;
        }

        // 检查距离上次推理的时间是否小于设定间隔
        let now = Instant::now();
        if now.duration_since(last_inference_time) < inference_interval {
            continue;
        }

        // 记录推理开始时间
        let inference_start = Instant::now();

        // 计算最大样本数（现在要使用16000采样率）
        let max_samples = max_audio_duration * 16000;

        // 计算总长度
        let total_len = history_pcm.len() + buffered_pcm.len();

        // 如果总长度超过最大样本限制，调整history_pcm
        let mut adjusted_history_pcm = history_pcm.clone();
        if total_len > max_samples {
            // 计算需要从history_pcm中减去的长度
            let excess = total_len - max_samples;
            println!(
                "history_pcm len: {} buffered_pcm len: {} excess: {}",
                history_pcm.len(),
                buffered_pcm.len(),
                excess
            );
            // 如果history_pcm长度大于excess，保留后面部分
            if history_pcm.len() > excess {
                adjusted_history_pcm = history_pcm[excess..].to_vec();
            } else {
                // 如果history_pcm不够减，则不使用history_pcm
                adjusted_history_pcm = Vec::new();
            }
        }

        // 合并调整后的历史数据和新数据进行处理
        let mut combined_pcm = Vec::with_capacity(adjusted_history_pcm.len() + buffered_pcm.len());
        combined_pcm.extend_from_slice(&adjusted_history_pcm);
        combined_pcm.extend_from_slice(&buffered_pcm);

        // 更新历史数据为当前的组合数据
        history_pcm = combined_pcm.clone();

        // 清理缓冲区
        buffered_pcm.clear();

        let pcm = combined_pcm;

        let mut params = FullParams::new(SamplingStrategy::Greedy { best_of: 1 });
        params.set_print_special(with_timestamps.unwrap_or(false));
        params.set_language(arg_language.as_deref().unwrap_or("en"));
        params.set_translate(false);
        params.set_no_speech_threshold(0.6);
        params.set_logprob_threshold(-1.0);
        params.set_temperature([0.0]);

        let mut state = whisper_state.clone();
        let segments = state.full(params, &pcm)?;

        let inference_duration = inference_start.elapsed();
        let audio_duration = (pcm.len() as f32 / 16000.0 * 1000.0) as u128;

        let mut segments_with_metadata: Vec<whisper_rs::Segment> = segments
            .into_iter()
            .map(|segment| whisper_rs::Segment {
                start: segment.start,
                end: segment.end,
                text: segment.text,
                tokens: segment.tokens,
                avg_logprob: segment.avg_logprob,
                no_speech_prob: segment.no_speech_prob,
                temperature: segment.temperature,
                compression_ratio: segment.compression_ratio,
                status: whisper_rs::WhisperStatus::Working,
                reasoning_duration: Some(inference_duration.as_millis()),
                reasoning_lang: language_token_name.clone(),
                audio_duration: Some(audio_duration),
            })
            .collect();

        result_callback(segments_with_metadata);
        last_inference_time = now;
    }

    tokio::select! {
        _ = cancel_token.cancelled() => {
            println!("Transcription cancelled");
        }
        _ = processor_task => {
            println!("Processor task completed");
        }
    }

    let _ = audio_thread.join();

    result_callback(_make_status_response(whisper_rs::WhisperStatus::Exit));

    println!("Whisper Exit");
    Ok(())
}

fn _make_status_response(status: whisper_rs::WhisperStatus) -> Vec<whisper_rs::Segment> {
    vec![whisper_rs::Segment {
        start: 0.0,
        end: 0.0,
        text: "".to_string(),
        tokens: vec![],
        avg_logprob: 0.0,
        no_speech_prob: 0.0,
        temperature: 0.0,
        compression_ratio: 0.0,
        status,
        reasoning_duration: None,
        reasoning_lang: None,
        audio_duration: None,
    }]
}

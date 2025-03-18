pub mod multilingual;
pub mod whisper;

use std::time::Duration;

use crate::whisper_caption::whisper::{Model, Segment};
use candle_nn::VarBuilder;
use candle_transformers::models::whisper::{self as m, audio, Config};
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use native_dialog::{MessageDialog, MessageType};
use std::sync::mpsc as std_mpsc;
use std::{panic, thread};
use tokenizers::Tokenizer;
use tokio::sync::mpsc;
use tokio::time::Instant;
use tokio_util::sync::CancellationToken;

pub async fn launch_caption<F>(
    model_path: String,
    config_data: &str,
    is_quantized: bool,
    tokenizer_data: Vec<u8>,
    audio_device: Option<String>,
    audio_device_is_input: Option<bool>,
    audio_language: Option<String>,
    is_multilingual: Option<bool>,
    cancel_token: CancellationToken,
    with_timestamps: Option<bool>,
    verbose: Option<bool>,
    try_with_cuda: bool,
    inference_timeout: Option<Duration>,   // 推理总超时参数
    max_tokens_per_segment: Option<usize>, // 防止幻觉的每段最大token数
    mut result_callback: F,
) -> anyhow::Result<()>
where
    F: FnMut(Vec<Segment>) + Send + 'static,
{
    result_callback(_make_status_response(whisper::WhisperStatus::Loading));
    let device = if try_with_cuda {
        if cfg!(target_os = "macos") {
            candle_core::Device::new_metal(0)?
        } else {
            _try_get_cuda()
        }
    } else {
        candle_core::Device::Cpu
    };

    let arg_is_multilingual = is_multilingual.unwrap_or(false);
    let arg_language = audio_language;
    let arg_device = audio_device;
    let is_input = audio_device_is_input.unwrap_or(true);

    let config: Config = serde_json::from_str(config_data)?;
    let tokenizer = Tokenizer::from_bytes(tokenizer_data).unwrap();

    // check model path
    if !std::path::Path::new(&model_path).exists() {
        anyhow::bail!("model path does not exist: {model_path}");
    }

    let model = if is_quantized {
        let vb = candle_transformers::quantized_var_builder::VarBuilder::from_gguf(
            &model_path,
            &device,
        )?;
        Model::Quantized(m::quantized_model::Whisper::load(&vb, config.clone())?)
    } else {
        let vb = unsafe { VarBuilder::from_mmaped_safetensors(&[model_path], m::DTYPE, &device)? };
        Model::Normal(m::model::Whisper::load(&vb, config.clone())?)
    };
    let seed = 299792458;
    let mut decoder = whisper::Decoder::new(
        model,
        tokenizer.clone(),
        seed,
        &device,
        /* language_token */ None,
        Some(whisper::Task::Transcribe),
        with_timestamps.unwrap_or(false),
        verbose.unwrap_or(false),
    )?;

    let mel_bytes = match config.num_mel_bins {
        80 => include_bytes!("../../whisper/melfilters.bytes").as_slice(),
        128 => include_bytes!("../../whisper/melfilters128.bytes").as_slice(),
        nmel => anyhow::bail!("unexpected num_mel_bins {nmel}"),
    };
    let mut mel_filters = vec![0f32; mel_bytes.len() / 4];
    <byteorder::LittleEndian as byteorder::ByteOrder>::read_f32_into(mel_bytes, &mut mel_filters);

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

    result_callback(_make_status_response(whisper::WhisperStatus::Ready));
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

        let mel = audio::pcm_to_mel(&config, &pcm, &mel_filters);
        let mel_len = mel.len();
        let mel = candle_core::Tensor::from_vec(
            mel,
            (1, config.num_mel_bins, mel_len / config.num_mel_bins),
            &device,
        )?;

        if !language_token_set {
            let language_token = match (arg_is_multilingual, arg_language.clone()) {
                (true, None) => Some(multilingual::detect_language(
                    decoder.model(),
                    &tokenizer,
                    &mel,
                )?),
                (false, None) => None,
                (true, Some(language)) => {
                    match whisper::token_id(&tokenizer, &format!("<|{language}|>")) {
                        Ok(token_id) => Some(token_id),
                        Err(_) => anyhow::bail!("language {language} is not supported"),
                    }
                }
                (false, Some(_)) => {
                    anyhow::bail!("a language cannot be set for non-multilingual models")
                }
            };
            decoder.set_language_token(language_token);
            language_token_set = true;
            language_token_name = match language_token {
                Some(token) => whisper::get_token_name_by_id(&tokenizer, token),
                None => None,
            };
            println!(
                "language_token: {:?} language_name: {:?}",
                language_token, language_token_name
            );
        }

        // 运行解码器并获取结果
        let mut segments = decoder.run(&mel, None, inference_timeout, max_tokens_per_segment)?;
        // 计算推理用时并输出
        let inference_duration = inference_start.elapsed();

        let audio_duration = (pcm.len() as f32 / 16000.0 * 1000.0) as u128;

        for segment in &mut segments {
            segment.reasoning_duration = Some(inference_duration.as_millis());
            segment.reasoning_lang = language_token_name.clone();
            segment.audio_duration = Some(audio_duration);
        }

        // 发送结果并更新推理时间
        result_callback(segments);
        decoder.reset_kv_cache();
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

    result_callback(_make_status_response(whisper::WhisperStatus::Exit));

    println!("Whisper Exit");
    Ok(())
}

fn _try_get_cuda() -> candle_core::Device {
    // get a cuda device
    let result = panic::catch_unwind(|| candle_core::Device::cuda_if_available(0).unwrap());
    result.unwrap_or_else(|panic_err| {
        // 尝试从 panic 值中提取有用信息
        let panic_info = if let Some(s) = panic_err.downcast_ref::<String>() {
            s.clone()
        } else if let Some(s) = panic_err.downcast_ref::<&str>() {
            s.to_string()
        } else {
            "Unknow CUDA device initialization error".to_string()
        };
        // show dialog
        MessageDialog::new()
            .set_type(MessageType::Error)
            .set_title("CUDA device initialization error , fall back to CPU")
            .set_text(&panic_info)
            .show_alert()
            .unwrap_or(());
        eprintln!("CUDA device initialization error {}", panic_info);
        // 返回 CPU 设备
        candle_core::Device::Cpu
    })
}

fn _make_status_response(status: whisper::WhisperStatus) -> Vec<Segment> {
    vec![Segment {
        start: 0.0,
        duration: 0.0,
        dr: whisper::DecodingResult {
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

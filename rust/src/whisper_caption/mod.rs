pub mod multilingual;
pub mod whisper;

use std::time::Duration;

use crate::audio_capture::{AudioCapture, AudioCaptureConfig, PlatformAudioCapture};
use crate::whisper_caption::whisper::{Model, Segment};
use crate::{get_device, vad};
use candle_nn::VarBuilder;
use candle_transformers::models::whisper::{self as m, audio, Config};
use tokenizers::Tokenizer;
use tokio::time::Instant;
use tokio_util::sync::CancellationToken;


pub struct LaunchCaptionParams {
    pub model_path: String,
    pub config_data: String,
    pub is_quantized: bool,
    pub tokenizer_data: Vec<u8>,
    pub audio_device: Option<String>,
    pub audio_device_is_input: Option<bool>,
    pub audio_language: Option<String>,
    pub is_multilingual: Option<bool>,
    pub cancel_token: CancellationToken,
    pub with_timestamps: Option<bool>,
    pub verbose: Option<bool>,
    pub try_with_cuda: bool,
    pub inference_timeout: Option<Duration>,     // 推理总超时参数
    pub max_tokens_per_segment: Option<usize>,   // 防止幻觉的每段最大token数
    pub whisper_max_audio_duration: Option<u32>, // 音频上下文长度(秒)
    pub inference_interval_ms: Option<u64>,      // 推理间隔时间(毫秒)
    pub whisper_temperature: Option<f32>,        // 温度参数
    pub vad_model_path: Option<String>,          // VAD模型路径
    pub vad_filters_value: Option<f32>,          // VAD模型阈值
}

pub async fn launch_caption<F>(
    params: LaunchCaptionParams,
    mut result_callback: F,
) -> anyhow::Result<()> 
where
    F: FnMut(Vec<Segment>) + Send + 'static,
{
    let LaunchCaptionParams {
        model_path,
        config_data,
        is_quantized,
        tokenizer_data,
        audio_device,
        audio_device_is_input,
        audio_language,
        is_multilingual,
        cancel_token,
        with_timestamps,
        verbose,
        try_with_cuda,
        inference_timeout,
        max_tokens_per_segment,
        whisper_max_audio_duration,
        inference_interval_ms,
        whisper_temperature,
        vad_model_path,
        vad_filters_value,
    } = params;

    result_callback(_make_status_response(whisper::WhisperStatus::Loading));
    let device = get_device(try_with_cuda)?;
    let arg_is_multilingual = is_multilingual.unwrap_or(false);
    let arg_language = audio_language;
    let arg_device = audio_device;
    let is_input = audio_device_is_input.unwrap_or(true);

    let config: Config = serde_json::from_str(&config_data)?;
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
        80 => include_bytes!("../../assets/whisper/melfilters.bytes").as_slice(),
        128 => include_bytes!("../../assets/whisper/melfilters128.bytes").as_slice(),
        nmel => anyhow::bail!("unexpected num_mel_bins {nmel}"),
    };
    let mut mel_filters = vec![0f32; mel_bytes.len() / 4];
    <byteorder::LittleEndian as byteorder::ByteOrder>::read_f32_into(mel_bytes, &mut mel_filters);

    // Set up audio capture using the abstracted interface
    let audio_capture_config = AudioCaptureConfig {
        device: arg_device,
        is_input,
        target_sample_rate: 16000,
        target_channels: 1,
    };

    let audio_capture = PlatformAudioCapture::new(audio_capture_config)?;
    let audio_info = audio_capture.get_info();
    println!("Audio capture info: {:?}", audio_info);

    // Start audio capture
    let rx = audio_capture.start_capture(cancel_token.child_token())?;

    result_callback(_make_status_response(whisper::WhisperStatus::Ready));
    println!("Whisper Ready...");

    // 处理任务在当前函数中运行
    let mut buffered_pcm = vec![];
    let mut history_pcm = Vec::new();
    let mut last_inference_time = Instant::now();
    // let mut last_vad_passed_time = Instant::now();
    let mut first_inference_done = false;
    let inference_interval = Duration::from_millis(inference_interval_ms.unwrap_or(2000)); // 默认2000毫秒
    let max_audio_duration: usize = whisper_max_audio_duration.unwrap_or(12) as usize; // 默认12秒
    let mut language_token_set = false;
    let mut language_token_name: Option<String> = None;
    let fixed_temperature = whisper_temperature;

    println!("Check and loading vad model...");
    let vad_model = if let Some(vad_model_path) = vad_model_path {
        // try_with_gpu: [false] candle-onnx not support gpu
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

    // 处理循环
    println!("Starting audio processing loop...");
    let mut debug_counter = 0;
    while !cancel_token.is_cancelled() {
        debug_counter += 1;
        if debug_counter % 500 == 0 {  // 每50秒打印一次调试信息
            println!("Audio processing loop iteration {}, buffered_pcm.len(): {}", debug_counter, buffered_pcm.len());
        }
        
        // 尝试接收音频数据，设置超时以便定期检查取消状态
        let pcm = rx.recv_timeout(Duration::from_millis(100));

        // 如果接收超时或通道关闭，检查是否应该取消
        if pcm.is_err() {
            let err = pcm.unwrap_err();
            if debug_counter % 1000 == 0 {  // 每100秒打印一次超时信息
                println!("Audio recv timeout or error: {:?}, cancel_token cancelled: {}", err, cancel_token.is_cancelled());
            }
            if cancel_token.is_cancelled() {
                break;
            }
            continue;
        }

        // 处理接收到的音频数据
        let pcm = pcm.unwrap();
        
        static mut AUDIO_RECEIVED: bool = false;
        unsafe {
            if !AUDIO_RECEIVED {
                println!("First audio data received: {} samples", pcm.len());
                AUDIO_RECEIVED = true;
            } else if pcm.len() > 0 && debug_counter % 100 == 0 {
                println!("Audio data: {} samples (debug every 100 iterations)", pcm.len());
            }
        }

        buffered_pcm.extend_from_slice(&pcm);
        
        if buffered_pcm.len() > 0 && (buffered_pcm.len() % 16000 == 0 || debug_counter % 200 == 0) {
            println!("Total buffered_pcm length: {} samples ({:.1}s)", buffered_pcm.len(), buffered_pcm.len() as f32 / 16000.0);
        }

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

        // 如果最后有效推理间隔大于设定间隔的两倍，则清空历史音频 （考虑到自然停顿等）
        // if now.duration_since(last_vad_passed_time) > inference_interval * 2 {
        //     println!("Clearing buffered_pcm due to long silence");
        //     history_pcm.clear();
        // }

        // 记录推理开始时间
        let inference_start = Instant::now();

        if let Some(vad_model) = &vad_model {
            let resampled_pcm = buffered_pcm.clone();
            let vad_result = vad_model.check_vad(resampled_pcm, vad_filters_value);
            if vad_result.is_err() {
                println!("VAD error: {:?}", vad_result.err().unwrap());
            } else {
                let vad_result = vad_result?;
                println!(
                    "VAD prediction: {:?} filtered_count: {:?}",
                    vad_result.prediction, vad_result.filtered_count
                );
                if vad_result.prediction > vad_filters_value.unwrap_or(0.1) {
                    buffered_pcm = vad_result.pcm_results;
                    // last_vad_passed_time = Instant::now();
                } else {
                    buffered_pcm.clear();
                    last_inference_time = Instant::now();
                    continue;
                }
            }
        }

        // 计算最大样本数（使用16000采样率）
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
        let mut segments = decoder.run(
            &mel,
            None,
            inference_timeout.or(Some(inference_interval)),
            max_tokens_per_segment,
            fixed_temperature,
        )?;
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

    println!("Transcription cancelled");
    result_callback(_make_status_response(whisper::WhisperStatus::Exit));

    println!("Whisper Exit");
    Ok(())
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

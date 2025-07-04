use kaldi_fbank_rust::{FbankOptions, OnlineFbank};
use ndarray::{Array1, Array2, Axis};
use ort::session::Session;
use std::collections::HashMap;
use std::time::Duration;

use crate::candle_models::whisper::model::{DecodingResult, Segment, WhisperStatus};
use crate::candle_models::whisper::LaunchCaptionParams;

mod def;

pub struct SenseVoiceModel {
    session: Session,
    window_size: i32,  // lfr_m
    window_shift: i32, // lfr_n
    lang_id: HashMap<String, i32>,
    with_itn: i32,
    without_itn: i32,
    neg_mean: Vec<f32>,
    inv_stddev: Vec<f32>,
}

impl SenseVoiceModel {
    pub fn from_session(session: Session) -> anyhow::Result<Self> {
        // 尝试获取自定义元数据，如果失败则使用默认值

        // 从模型元数据中获取参数
        let mut window_size = 7; // 默认值
        let mut window_shift = 6; // 默认值
        let mut with_itn = 1; // 默认值
        let without_itn = 0;

        // 尝试从metadata获取实际参数
        if let Ok(metadata) = session.metadata() {
            if let Ok(Some(lfr_window_size)) = metadata.custom("lfr_window_size") {
                if let Ok(size) = lfr_window_size.parse::<i32>() {
                    window_size = size;
                }
            }
            if let Ok(Some(lfr_window_shift)) = metadata.custom("lfr_window_shift") {
                if let Ok(shift) = lfr_window_shift.parse::<i32>() {
                    window_shift = shift;
                }
            }
            if let Ok(Some(with_itn_str)) = metadata.custom("with_itn") {
                if let Ok(itn) = with_itn_str.parse::<i32>() {
                    with_itn = itn;
                }
            }
        }

        // 语言ID映射
        let mut lang_id = HashMap::new();
        lang_id.insert("zh".to_string(), 0);
        lang_id.insert("en".to_string(), 1);
        lang_id.insert("ja".to_string(), 2);
        lang_id.insert("ko".to_string(), 3);
        lang_id.insert("auto".to_string(), 4);

        // 归一化参数 - 根据window_size动态计算维度
        let feature_dim = 80 * window_size as usize;
        let mut neg_mean = vec![0.0; feature_dim];
        let mut inv_stddev = vec![1.0; feature_dim];

        // 从metadata获取归一化参数
        if let Ok(metadata) = session.metadata() {
            if let Ok(Some(inv_stddev_str)) = metadata.custom("inv_stddev") {
                let values: Vec<f32> = inv_stddev_str
                    .split(',')
                    .filter_map(|s| s.trim().parse().ok())
                    .collect();
                if values.len() == feature_dim {
                    inv_stddev = values;
                }
            }
            if let Ok(Some(neg_mean_str)) = metadata.custom("neg_mean") {
                let values: Vec<f32> = neg_mean_str
                    .split(',')
                    .filter_map(|s| s.trim().parse().ok())
                    .collect();
                if values.len() == feature_dim {
                    neg_mean = values;
                }
            }
        }

        println!("SenseVoice model parameters loaded:");
        println!("  - window_size (lfr_m): {}", window_size);
        println!("  - window_shift (lfr_n): {}", window_shift);
        println!("  - with_itn: {}, without_itn: {}", with_itn, without_itn);
        println!(
            "  - neg_mean length: {}, inv_stddev length: {}",
            neg_mean.len(),
            inv_stddev.len()
        );
        println!("  - language mappings: {:?}", lang_id);

        // 尝试打印可用的元数据信息用于调试
        if let Ok(metadata) = session.metadata() {
            println!("Available metadata:");
            println!("  - version: {:?}", metadata.version());
            println!("  - with_itn: {:?}", metadata.custom("with_itn"));
            println!(
                "  - lfr_window_size: {:?}",
                metadata.custom("lfr_window_size")
            );
            println!(
                "  - lfr_window_shift: {:?}",
                metadata.custom("lfr_window_shift")
            );
        }

        // 打印模型的输入信息用于调试
        println!("Model inputs:");
        for input in session.inputs.iter() {
            println!("  - name: {}, type: {:?}", input.name, input.input_type);
        }

        // 打印模型的输出信息用于调试
        println!("Model outputs:");
        for output in session.outputs.iter() {
            println!("  - name: {}, type: {:?}", output.name, output.output_type);
        }

        Ok(Self {
            session,
            window_size,
            window_shift,
            lang_id,
            with_itn,
            without_itn,
            neg_mean,
            inv_stddev,
        })
    }

    #[allow(dead_code)]
    pub fn inference(
        &mut self,
        features: Array2<f32>,
        language: &str,
        use_itn: bool,
    ) -> anyhow::Result<Array2<f32>> {
        use ort::value::Value;

        let seq_len = features.shape()[0];

        // 准备输入张量
        let x = features.insert_axis(Axis(0)); // [1, T, D] - 添加batch维度

        // 根据模型输入要求，x_length, language, text_norm 需要是 i32 类型
        let x_length = Array1::from_vec(vec![seq_len as i32]);

        let language_id = self
            .lang_id
            .get(language)
            .copied()
            .unwrap_or(self.lang_id.get("auto").copied().unwrap_or(4));
        let language_tensor = Array1::from_vec(vec![language_id]);

        let text_norm_id = if use_itn {
            self.with_itn
        } else {
            self.without_itn
        };
        let text_norm_tensor = Array1::from_vec(vec![text_norm_id]);

        // to value
        let x_value = Value::from_array(x)?;
        let x_length_value = Value::from_array(x_length)?;
        let language_value = Value::from_array(language_tensor)?;
        let text_norm_value = Value::from_array(text_norm_tensor)?;

        let outputs = self.session.run(ort::inputs![
            "x" => x_value,
            "x_length" => x_length_value,
            "language" => language_value,
            "text_norm" => text_norm_value,
        ])?;

        // 获取输出
        let output_keys: Vec<_> = outputs.keys().collect();
        if output_keys.is_empty() {
            return Err(anyhow::anyhow!("No outputs from model"));
        }

        println!("Available output keys: {:?}", output_keys);

        // 尝试获取输出 - 常见的输出名称
        let logits_value = outputs
            .get("logits")
            .or_else(|| outputs.get("output"))
            .or_else(|| outputs.get("outputs"))
            .or_else(|| outputs.get(output_keys[0]))
            .ok_or_else(|| anyhow::anyhow!("Cannot find model output"))?;

        // 将ONNX Value转换为ndarray
        match logits_value.try_extract_tensor::<f32>() {
            Ok(tensor_data) => {
                let (shape, data) = tensor_data;

                // 假设输出形状为 [batch, seq_len, vocab_size] 或 [seq_len, vocab_size]
                if shape.len() < 2 {
                    return Err(anyhow::anyhow!(
                        "Expected at least 2D output tensor, got {}D",
                        shape.len()
                    ));
                }

                // 处理不同的输出形状，转换为usize
                let (seq_len_out, vocab_size) = if shape.len() == 3 {
                    // 形状为 [batch, seq_len, vocab_size]
                    let batch_size = shape[0] as usize;
                    if batch_size != 1 {
                        return Err(anyhow::anyhow!("Expected batch size 1, got {}", batch_size));
                    }
                    (shape[1] as usize, shape[2] as usize)
                } else {
                    // 形状为 [seq_len, vocab_size]
                    (shape[0] as usize, shape[1] as usize)
                };

                // 创建2D数组 [seq_len, vocab_size]
                let mut logits = Array2::zeros((seq_len_out, vocab_size));

                // 计算数据偏移量
                let data_offset = if shape.len() == 3 { 0 } else { 0 };

                for i in 0..seq_len_out {
                    for j in 0..vocab_size {
                        let idx = data_offset + i * vocab_size + j;
                        if idx < data.len() {
                            logits[[i, j]] = data[idx];
                        }
                    }
                }

                Ok(logits)
            }
            Err(e) => Err(anyhow::anyhow!("Failed to extract tensor: {}", e)),
        }
    }
}

#[allow(dead_code)]
fn load_tokens(tokens_path: &str) -> anyhow::Result<HashMap<usize, String>> {
    let content = std::fs::read_to_string(tokens_path)?;
    let mut tokens = HashMap::new();

    for (i, line) in content.lines().enumerate() {
        if let Some(token) = line.split_whitespace().next() {
            tokens.insert(i, token.to_string());
        }
    }

    Ok(tokens)
}

fn compute_features(
    samples: &[f32],
    sample_rate: f32,
    neg_mean: &[f32],
    inv_stddev: &[f32],
    window_size: i32,
    window_shift: i32,
) -> anyhow::Result<Array2<f32>> {
    // 配置fbank参数
    let mut fbank_opts = FbankOptions::default();
    fbank_opts.frame_opts.dither = 0.0;
    fbank_opts.frame_opts.snip_edges = false;
    fbank_opts.frame_opts.samp_freq = sample_rate;
    // 设置hamming窗口
    fbank_opts.frame_opts.window_type = std::ffi::CStr::from_bytes_with_nul(b"hamming\0")
        .unwrap()
        .as_ptr(); // "hamming";
    fbank_opts.mel_opts.num_bins = 80;

    let mut online_fbank = OnlineFbank::new(fbank_opts);

    // 将样本缩放到16位整数范围然后转换为f32
    let scaled_samples: Vec<f32> = samples.iter().map(|&x| x * 32768.0).collect();
    online_fbank.accept_waveform(sample_rate, &scaled_samples);
    online_fbank.input_finished();

    let num_frames = online_fbank.num_ready_frames();
    if num_frames == 0 {
        return Err(anyhow::anyhow!("No frames ready"));
    }

    // 提取所有帧的特征
    let mut features = Vec::with_capacity(num_frames as usize);
    for i in 0..num_frames {
        if let Some(frame) = online_fbank.get_frame(i) {
            features.push(frame.to_vec());
        }
    }

    if features.is_empty() {
        return Err(anyhow::anyhow!("No features extracted"));
    }

    let feature_dim = features[0].len();
    let mut feature_matrix = Array2::zeros((features.len(), feature_dim));

    for (i, frame) in features.iter().enumerate() {
        for (j, &val) in frame.iter().enumerate() {
            feature_matrix[[i, j]] = val;
        }
    }

    // 应用LFR (Low Frame Rate) 处理
    let lfr_features = apply_lfr(&feature_matrix, window_size, window_shift)?;

    // 应用归一化
    let normalized_features = apply_normalization(&lfr_features, neg_mean, inv_stddev)?;

    Ok(normalized_features)
}

#[allow(dead_code)]
fn apply_lfr(
    features: &Array2<f32>,
    window_size: i32,
    window_shift: i32,
) -> anyhow::Result<Array2<f32>> {
    let (num_frames, feature_dim) = features.dim();

    if num_frames < window_size as usize {
        return Err(anyhow::anyhow!("Not enough frames for LFR processing"));
    }

    let t = (num_frames - window_size as usize) / window_shift as usize + 1;
    let output_dim = feature_dim * window_size as usize;

    let mut lfr_features = Array2::zeros((t, output_dim));

    for i in 0..t {
        let start_frame = i * window_shift as usize;
        for j in 0..window_size as usize {
            let frame_idx = start_frame + j;
            let output_start = j * feature_dim;
            for k in 0..feature_dim {
                lfr_features[[i, output_start + k]] = features[[frame_idx, k]];
            }
        }
    }

    Ok(lfr_features)
}

fn apply_normalization(
    features: &Array2<f32>,
    neg_mean: &[f32],
    inv_stddev: &[f32],
) -> anyhow::Result<Array2<f32>> {
    let mut normalized = features.clone();

    for mut row in normalized.rows_mut() {
        for (i, val) in row.iter_mut().enumerate() {
            if i < neg_mean.len() && i < inv_stddev.len() {
                *val = (*val + neg_mean[i]) * inv_stddev[i];
            }
        }
    }

    Ok(normalized)
}

fn parse_sensevoice_output(
    logits: &Array2<f32>,
    tokens: &HashMap<usize, String>,
) -> def::SenseVoiceOutput {
    // 获取最大概率的token索引
    let indices: Vec<usize> = logits
        .rows()
        .into_iter()
        .map(|row| {
            row.iter()
                .enumerate()
                .max_by(|a, b| a.1.partial_cmp(b.1).unwrap())
                .map(|(idx, _)| idx)
                .unwrap_or(0)
        })
        .collect();

    // 去除连续重复的token
    let mut unique_indices = Vec::new();
    let mut prev_idx = None;
    for idx in indices {
        if prev_idx != Some(idx) {
            unique_indices.push(idx);
            prev_idx = Some(idx);
        }
    }

    // 去除blank token (通常是0)
    let blank_id = 0;
    unique_indices.retain(|&idx| idx != blank_id);

    // 转换为token字符串
    let token_strings: Vec<String> = unique_indices
        .iter()
        .filter_map(|&idx| tokens.get(&idx))
        .map(|token| token.to_string())
        .collect();

    // 将所有token连接成一个字符串进行初步处理
    let full_text = token_strings.join("");

    // 解析特殊标记
    let mut language = None;
    let mut emotion = None;
    let mut event = None;
    let mut text_norm = None;
    let mut text_parts = Vec::new();
    let mut emoji_parts = Vec::new();

    // 处理特殊的组合标记
    let processed_text = full_text.replace("<|nospeech|><|Event_UNK|>", "❓"); // 特殊组合标记

    // 使用正则表达式或简单的字符串匹配来提取特殊标记和普通文本
    let mut remaining_text = processed_text.as_str();

    // 按顺序处理各种标记
    while let Some(start) = remaining_text.find("<|") {
        // 添加标记前的文本
        if start > 0 {
            let before_text = &remaining_text[..start];
            if !before_text.trim().is_empty() {
                text_parts.push(before_text.to_string());
            }
        }

        // 查找标记结束
        if let Some(end) = remaining_text[start..].find("|>") {
            let tag_end = start + end + 2;
            let tag = &remaining_text[start..tag_end];

            // 解析标记
            if let Some(lang) = def::SenseVoiceLanguage::from_token(tag) {
                language = Some(lang.clone());
                let emoji = lang.to_emoji();
                if !emoji.is_empty() {
                    emoji_parts.push(emoji.to_string());
                }
            } else if let Some(emo) = def::SenseVoiceEmotion::from_token(tag) {
                emotion = Some(emo.clone());
                let emoji = emo.to_emoji();
                if !emoji.is_empty() {
                    emoji_parts.push(emoji.to_string());
                }
            } else if let Some(evt) = def::SenseVoiceEvent::from_token(tag) {
                event = Some(evt.clone());
                let emoji = evt.to_emoji();
                if !emoji.is_empty() {
                    emoji_parts.push(emoji.to_string());
                }
            } else if let Some(norm) = def::SenseVoiceTextNorm::from_token(tag) {
                text_norm = Some(norm);
            }
            // 其他未识别的标记被忽略

            remaining_text = &remaining_text[tag_end..];
        } else {
            // 如果没有找到结束标记，将剩余部分作为文本
            text_parts.push(remaining_text.to_string());
            break;
        }
    }

    // 添加剩余的文本
    if !remaining_text.is_empty() && !remaining_text.trim().is_empty() {
        text_parts.push(remaining_text.to_string());
    }

    // 合并文本并清理
    let text = text_parts.join("").replace("▁", " ").trim().to_string();

    let emoji = emoji_parts.join("");

    def::SenseVoiceOutput {
        language,
        emotion,
        event,
        text_norm,
        text,
        emoji,
    }
}

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
        tokenizer_data,
        inference_timeout,
        inference_interval_ms,
        vad_model_path,
        vad_filters_value,
        whisper_max_audio_duration,
        ..
    } = params;

    let model_path = super::find_model_path(&models, None).unwrap();
    let session = super::init_model(model_path, params.try_with_cuda)?;
    // 初始化SenseVoice模型
    result_callback(_make_status_response(WhisperStatus::Loading));
    let mut model = SenseVoiceModel::from_session(session)?;

    // 加载tokens映射
    let tokenizer_str = std::str::from_utf8(&tokenizer_data)?;
    let tokens = load_tokens_from_data(tokenizer_str)?;

    // 设置音频捕获配置
    let audio_capture_config = AudioCaptureConfig {
        device: audio_device,
        is_input: audio_device_is_input.unwrap_or(true),
        target_sample_rate: 16000,
        target_channels: 1,
    };

    let audio_capture = PlatformAudioCapture::new(audio_capture_config)?;
    let audio_info = audio_capture.get_info();
    println!("SenseVoice Audio capture info: {:?}", audio_info);

    // 开始音频捕获
    let rx = audio_capture.start_capture(cancel_token.child_token())?;

    result_callback(_make_status_response(WhisperStatus::Ready));
    println!("SenseVoice Ready...");

    // 初始化音频处理状态
    let mut buffered_pcm = vec![];
    let mut history_pcm = Vec::new();
    let mut last_inference_time = Instant::now();
    let mut first_inference_done = false;
    let inference_interval = Duration::from_millis(inference_interval_ms.unwrap_or(2000)); // 默认2000毫秒
    let max_audio_duration: usize = whisper_max_audio_duration.unwrap_or(12) as usize; // 默认12秒
    let language = audio_language.as_deref().unwrap_or("auto"); // SenseVoice语言设置

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
    println!("Starting SenseVoice audio processing loop...");
    let mut debug_counter = 0;

    while !cancel_token.is_cancelled() {
        debug_counter += 1;
        if debug_counter % 500 == 0 {
            println!(
                "SenseVoice audio processing loop iteration {}, buffered_pcm.len(): {}",
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
                println!(
                    "SenseVoice first audio data received: {} samples",
                    pcm.len()
                );
                AUDIO_RECEIVED = true;
            } else if pcm.len() > 0 && debug_counter % 100 == 0 {
                println!(
                    "SenseVoice audio data: {} samples (debug every 100 iterations)",
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
                    "SenseVoice VAD prediction: {:?} filtered_count: {:?}",
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

        // 音频长度管理 - 与Whisper相同的逻辑
        let max_samples = max_audio_duration * 16000;
        let total_len = history_pcm.len() + buffered_pcm.len();

        let mut adjusted_history_pcm = history_pcm.clone();
        if total_len > max_samples {
            let excess = total_len - max_samples;
            println!(
                "SenseVoice history_pcm len: {} buffered_pcm len: {} excess: {}",
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

        // SenseVoice特征提取和推理
        match run_sensevoice_inference(
            &mut model,
            &pcm,
            language,
            &tokens,
            inference_timeout.or(Some(inference_interval)),
        ) {
            Ok(segments) => {
                let inference_duration = inference_start.elapsed();
                let audio_duration = (pcm.len() as f32 / 16000.0 * 1000.0) as u128;

                let mut result_segments = segments;
                for segment in &mut result_segments {
                    segment.reasoning_duration = Some(inference_duration.as_millis());
                    segment.reasoning_lang = Some(language.to_string());
                    segment.audio_duration = Some(audio_duration);
                }

                result_callback(result_segments);
            }
            Err(e) => {
                println!("SenseVoice inference error: {:?}", e);
                // 发送错误状态
                result_callback(_make_status_response(WhisperStatus::Error));
            }
        }

        last_inference_time = now;
    }

    println!("SenseVoice transcription cancelled");
    result_callback(_make_status_response(WhisperStatus::Exit));
    println!("SenseVoice Exit");
    Ok(())
}

// SenseVoice推理辅助函数
fn run_sensevoice_inference(
    model: &mut SenseVoiceModel,
    pcm: &[f32],
    language: &str,
    tokens: &HashMap<usize, String>,
    #[allow(unused_variables)] timeout: Option<Duration>,
) -> anyhow::Result<Vec<Segment>> {
    // 计算特征
    let features = compute_features(
        pcm,
        16000.0,
        &model.neg_mean,
        &model.inv_stddev,
        model.window_size,
        model.window_shift,
    )?;

    // 运行推理
    let use_itn = false; // 可以根据需要配置
    let logits = model.inference(features, language, use_itn)?;

    // 解析SenseVoice输出
    let parsed_output = parse_sensevoice_output(&logits, tokens);

    // 打印调试信息
    println!("SenseVoice parsed output:");
    println!("  Language: {:?}", parsed_output.language);
    println!("  Emotion: {:?}", parsed_output.emotion);
    println!("  Event: {:?}", parsed_output.event);
    println!("  Text norm: {:?}", parsed_output.text_norm);
    println!("  Emoji: {}", parsed_output.emoji);
    println!("  Clean text: {}", parsed_output.text);

    // 创建segment，只返回纯文本
    let duration = pcm.len() as f64 / 16000.0;
    let segment = Segment {
        start: 0.0,
        duration,
        dr: DecodingResult {
            tokens: vec![],           // SenseVoice暂不返回token序列
            text: parsed_output.text, // 只返回纯文本，不包含特殊标记
            avg_logprob: 0.0,
            no_speech_prob: 0.0,
            temperature: 0.0,
            compression_ratio: 1.0,
        },
        reasoning_duration: None,
        reasoning_lang: None,
        audio_duration: None,
        status: WhisperStatus::Working,
    };

    Ok(vec![segment])
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

fn load_tokens_from_data(data: &str) -> anyhow::Result<HashMap<usize, String>> {
    let mut tokens = HashMap::new();

    for (i, line) in data.lines().enumerate() {
        if let Some(token) = line.split_whitespace().next() {
            tokens.insert(i, token.to_string());
        }
    }

    Ok(tokens)
}

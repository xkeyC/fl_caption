use anyhow::Result;
use candle_transformers::models::whisper::{audio, Config};
use ndarray::{s, Array2, Array3, Array4};
use ort::{session::Session, value::Value};
use std::collections::HashMap;
use tokenizers::Tokenizer;

use crate::onnx_models::{find_model_path, init_model};

/// KV cache 窗口管理配置
#[derive(Debug, Clone)]
pub struct KvCacheConfig {
    /// 最大序列长度（KV cache 的最大长度）
    pub max_length: usize,
    /// 窗口管理策略
    pub strategy: KvCacheStrategy,
    /// 滑动窗口步长（仅在 SlidingWindow 策略下使用）
    pub sliding_step: usize,
}

/// KV cache 窗口管理策略
#[derive(Debug, Clone)]
pub enum KvCacheStrategy {
    /// 无限追加（默认行为，可能导致内存泄漏）
    Unlimited,
    /// 滑动窗口：当超过最大长度时，移除旧的 tokens 保留最新的
    SlidingWindow,
    /// 定期重置：当达到最大长度时，完全清空 KV cache
    Reset,
}

impl Default for KvCacheConfig {
    fn default() -> Self {
        Self {
            max_length: 1024, // 默认最大 1024 tokens
            strategy: KvCacheStrategy::SlidingWindow,
            sliding_step: 256, // 当超过最大长度时，移除前 256 个 tokens
        }
    }
}

/// Whisper ONNX模型输出结构
#[derive(Debug, Clone)]
pub struct Seq2SeqLMOutput {
    pub logits: Array3<f32>, // [batch_size, sequence_length, vocab_size]
    pub past_key_values: Option<Vec<(Array4<f32>, Array4<f32>)>>, // KV cache
}

/// Encoder输出结构
#[derive(Debug, Clone)]
pub struct BaseModelOutput {
    pub last_hidden_state: Array3<f32>, // [batch_size, sequence_length, hidden_size]
}

/// ONNX Whisper编码器
pub struct ORTEncoderForSpeech {
    session: Session,
}

impl ORTEncoderForSpeech {
    pub fn new(model_path: &str, try_gpu: bool) -> Result<Self> {
        let session = init_model(model_path.to_string(), try_gpu)?;
        Ok(Self { session })
    }

    /// 前向推理
    pub fn forward(&mut self, input_features: &Array3<f32>) -> Result<BaseModelOutput> {
        // 准备输入
        let input_value = Value::from_array(input_features.clone())?;

        // 运行推理
        let outputs = self.session.run(ort::inputs![
            "input_features" => input_value
        ])?;

        // 获取输出
        let last_hidden_state_value = outputs
            .get("last_hidden_state")
            .ok_or_else(|| anyhow::anyhow!("Missing last_hidden_state output"))?;

        // 提取张量数据
        let (shape, data) = last_hidden_state_value.try_extract_tensor::<f32>()?;

        // 验证形状
        if shape.len() != 3 {
            return Err(anyhow::anyhow!("Expected 3D tensor, got {}D", shape.len()));
        }

        let (batch_size, seq_len, hidden_size) =
            (shape[0] as usize, shape[1] as usize, shape[2] as usize);

        // 创建ndarray
        let mut last_hidden_state = Array3::zeros((batch_size, seq_len, hidden_size));
        for b in 0..batch_size {
            for s in 0..seq_len {
                for h in 0..hidden_size {
                    let idx = b * seq_len * hidden_size + s * hidden_size + h;
                    if idx < data.len() {
                        last_hidden_state[[b, s, h]] = data[idx];
                    }
                }
            }
        }

        Ok(BaseModelOutput { last_hidden_state })
    }
}

/// ONNX Whisper解码器
pub struct ORTDecoderForSeq2Seq {
    session_with_past: Session,
}

impl ORTDecoderForSeq2Seq {
    pub fn new(decoder_with_past_path: &str, try_gpu: bool) -> Result<Self> {
        let session_with_past = init_model(decoder_with_past_path.to_string(), try_gpu)?;

        Ok(Self { session_with_past })
    }

    /// 前向推理
    pub fn forward(
        &mut self,
        input_ids: &Array2<i64>,
        past_key_values: Option<&Vec<(Array4<f32>, Array4<f32>)>>,
    ) -> Result<Seq2SeqLMOutput> {
        // 根据是否有 past_key_values 来构建输入
        let outputs = if let Some(past_kv) = past_key_values {
            // 有 past_key_values，需要传递给模型
            let mut input_names = Vec::new();
            let mut input_values = Vec::new();

            // 添加基础输入
            input_names.push("input_ids".to_string());
            input_values.push(Value::from_array(input_ids.clone())?.into_dyn());

            for layer_idx in 0..4 {
                if layer_idx < past_kv.len() {
                    let (key, value) = &past_kv[layer_idx];
                    
                    // decoder key/value
                    let decoder_key_name = format!("past_key_values.{}.decoder.key", layer_idx);
                    let decoder_value_name = format!("past_key_values.{}.decoder.value", layer_idx);
                    input_names.push(decoder_key_name);
                    input_values.push(Value::from_array(key.clone())?.into_dyn());
                    input_names.push(decoder_value_name);
                    input_values.push(Value::from_array(value.clone())?.into_dyn());

                    // encoder key/value (在这个模型中，可能需要提供相同的值或零值)
                    let encoder_key_name = format!("past_key_values.{}.encoder.key", layer_idx);
                    let encoder_value_name = format!("past_key_values.{}.encoder.value", layer_idx);
                    input_names.push(encoder_key_name);
                    input_values.push(Value::from_array(key.clone())?.into_dyn());
                    input_names.push(encoder_value_name);
                    input_values.push(Value::from_array(value.clone())?.into_dyn());
                } else {
                    // 如果没有足够的KV cache，创建零张量
                    let batch_size = input_ids.shape()[0];
                    let zero_kv: Array4<f32> = Array4::zeros((batch_size, 20, 1, 64)); // 根据模型输出形状
                    
                    let decoder_key_name = format!("past_key_values.{}.decoder.key", layer_idx);
                    let decoder_value_name = format!("past_key_values.{}.decoder.value", layer_idx);
                    let encoder_key_name = format!("past_key_values.{}.encoder.key", layer_idx);
                    let encoder_value_name = format!("past_key_values.{}.encoder.value", layer_idx);
                    
                    input_names.push(decoder_key_name);
                    input_values.push(Value::from_array(zero_kv.clone())?.into_dyn());
                    input_names.push(decoder_value_name);
                    input_values.push(Value::from_array(zero_kv.clone())?.into_dyn());
                    input_names.push(encoder_key_name);
                    input_values.push(Value::from_array(zero_kv.clone())?.into_dyn());
                    input_names.push(encoder_value_name);
                    input_values.push(Value::from_array(zero_kv.clone())?.into_dyn());
                }
            }

            let inputs: Vec<(&str, Value)> = input_names
                .iter()
                .zip(input_values.into_iter())
                .map(|(name, value)| (name.as_str(), value))
                .collect();

            self.session_with_past.run(inputs)?
        } else {
            // 没有 past_key_values，需要提供零张量作为所有KV cache输入
            let mut input_names = Vec::new();
            let mut input_values = Vec::new();

            // 添加基础输入
            input_names.push("input_ids".to_string());
            input_values.push(Value::from_array(input_ids.clone())?.into_dyn());

            // 为所有4层提供零张量KV cache
            let batch_size = input_ids.shape()[0];
            for layer_idx in 0..4 {
                let zero_kv: Array4<f32> = Array4::zeros((batch_size, 20, 0, 64)); // 序列长度为0的空张量
                
                let decoder_key_name = format!("past_key_values.{}.decoder.key", layer_idx);
                let decoder_value_name = format!("past_key_values.{}.decoder.value", layer_idx);
                let encoder_key_name = format!("past_key_values.{}.encoder.key", layer_idx);
                let encoder_value_name = format!("past_key_values.{}.encoder.value", layer_idx);
                
                input_names.push(decoder_key_name);
                input_values.push(Value::from_array(zero_kv.clone())?.into_dyn());
                input_names.push(decoder_value_name);
                input_values.push(Value::from_array(zero_kv.clone())?.into_dyn());
                input_names.push(encoder_key_name);
                input_values.push(Value::from_array(zero_kv.clone())?.into_dyn());
                input_names.push(encoder_value_name);
                input_values.push(Value::from_array(zero_kv.clone())?.into_dyn());
            }

            let inputs: Vec<(&str, Value)> = input_names
                .iter()
                .zip(input_values.into_iter())
                .map(|(name, value)| (name.as_str(), value))
                .collect();

            self.session_with_past.run(inputs)?
        };

        // 获取logits
        let logits_value = outputs
            .get("logits")
            .ok_or_else(|| anyhow::anyhow!("Missing logits output"))?;

        let (logits_shape, logits_data) = logits_value.try_extract_tensor::<f32>()?;

        if logits_shape.len() != 3 {
            return Err(anyhow::anyhow!(
                "Expected 3D logits tensor, got {}D",
                logits_shape.len()
            ));
        }

        let (batch_size, seq_len, vocab_size) = (
            logits_shape[0] as usize,
            logits_shape[1] as usize,
            logits_shape[2] as usize,
        );

        // 验证 logits 数据长度
        let expected_logits_len = batch_size * seq_len * vocab_size;
        if logits_data.len() != expected_logits_len {
            return Err(anyhow::anyhow!(
                "Logits data length mismatch: expected {}, got {}",
                expected_logits_len,
                logits_data.len()
            ));
        }

        // 使用 from_shape_vec 更高效地创建 logits 数组
        let logits =
            Array3::from_shape_vec((batch_size, seq_len, vocab_size), logits_data.to_vec())
                .map_err(|e| anyhow::anyhow!("Failed to reshape logits tensor: {}", e))?;

        let mut past_key_values = None;
        let mut kv_cache = Vec::new();
        let mut layer_idx = 0;

        // 根据实际输出格式解析KV cache
        while let (Some(key_value), Some(value_value)) = (
            outputs.get(&format!("present.{}.decoder.key", layer_idx)),
            outputs.get(&format!("present.{}.decoder.value", layer_idx)),
        ) {
            let (key_shape, key_data) = key_value.try_extract_tensor::<f32>()?;
            let (value_shape, value_data) = value_value.try_extract_tensor::<f32>()?;

            if key_shape.len() != 4 || value_shape.len() != 4 {
                break;
            }

            // 验证 key 和 value 的形状一致性
            let key_dims = (
                key_shape[0] as usize,
                key_shape[1] as usize,
                key_shape[2] as usize,
                key_shape[3] as usize,
            );
            let value_dims = (
                value_shape[0] as usize,
                value_shape[1] as usize,
                value_shape[2] as usize,
                value_shape[3] as usize,
            );

            // 验证数据长度
            let expected_key_len = key_dims.0 * key_dims.1 * key_dims.2 * key_dims.3;
            let expected_value_len = value_dims.0 * value_dims.1 * value_dims.2 * value_dims.3;

            if key_data.len() != expected_key_len || value_data.len() != expected_value_len {
                return Err(anyhow::anyhow!(
                    "KV cache data length mismatch: key expected {}, got {}, value expected {}, got {}",
                    expected_key_len, key_data.len(), expected_value_len, value_data.len()
                ));
            }

            let key_tensor = Array4::from_shape_vec(key_dims, key_data.to_vec())
                .map_err(|e| anyhow::anyhow!("Failed to reshape key tensor: {}", e))?;

            let value_tensor = Array4::from_shape_vec(value_dims, value_data.to_vec())
                .map_err(|e| anyhow::anyhow!("Failed to reshape value tensor: {}", e))?;

            kv_cache.push((key_tensor, value_tensor));
            layer_idx += 1;
        }

        if !kv_cache.is_empty() {
            past_key_values = Some(kv_cache);
        }

        Ok(Seq2SeqLMOutput {
            logits,
            past_key_values,
        })
    }
}

/// ONNX Whisper主模型
pub struct ORTModelForWhisper {
    encoder: ORTEncoderForSpeech,
    decoder: ORTDecoderForSeq2Seq,
    tokenizer: Tokenizer,
    config: Config,
    decoder_start_token_id: i64,
    eos_token_id: i64,
    kv_cache_config: KvCacheConfig,
    /// 持久化的 KV cache
    persistent_kv_cache: Option<Vec<(Array4<f32>, Array4<f32>)>>,
    /// 当前持久化序列的长度（用于窗口管理）
    persistent_seq_len: usize,
}

impl ORTModelForWhisper {
    pub fn new(
        models: &HashMap<String, String>,
        tokenizer: Tokenizer,
        config: Config,
        try_gpu: bool,
        kv_cache_config: Option<KvCacheConfig>,
    ) -> Result<Self> {
        // 查找模型路径
        let encoder_path = find_model_path(models, Some("encoder"))
            .ok_or_else(|| anyhow::anyhow!("Encoder model not found"))?;

        let decoder_with_past_path = find_model_path(models, Some("decoder_with_past"))
            .ok_or_else(|| anyhow::anyhow!("Decoder with past model not found"))?;

        // 创建编码器和解码器
        let encoder = ORTEncoderForSpeech::new(&encoder_path, try_gpu)?;
        let decoder = ORTDecoderForSeq2Seq::new(&decoder_with_past_path, try_gpu)?;

        // print all input output names
        let encoder_input_names = encoder.session.inputs.iter().clone();
        let encoder_output_names = encoder.session.outputs.iter().clone();
        println!("Encoder input names: {:?}", encoder_input_names);
        println!("Encoder output names: {:?}", encoder_output_names);
        let decoder_input_names = decoder.session_with_past.inputs.iter().clone();
        let decoder_output_names = decoder.session_with_past.outputs.iter().clone();
        println!("Decoder input names: {:?}", decoder_input_names);
        println!("Decoder output names: {:?}", decoder_output_names);

        Ok(Self {
            encoder,
            decoder,
            tokenizer,
            config,
            decoder_start_token_id: 50258,
            eos_token_id: 50257,
            kv_cache_config: kv_cache_config.unwrap_or_default(),
            persistent_kv_cache: None,
            persistent_seq_len: 0,
        })
    }

    /// 前向推理
    pub fn forward(
        &mut self,
        input_features: &Array3<f32>,
        decoder_input_ids: &Array2<i64>,
        past_key_values: Option<&Vec<(Array4<f32>, Array4<f32>)>>,
    ) -> Result<Seq2SeqLMOutput> {
        // 编码器推理
        let _encoder_outputs = self.encoder.forward(input_features)?;

        // 解码器推理（注意：编码器输出在这个模型中不需要显式传递）
        self.decoder.forward(
            decoder_input_ids,
            past_key_values,
        )
    }

    pub fn generate(
        &mut self,
        encoder_hidden_states: &Array3<f32>,
        max_new_tokens: usize,
        temperature: f32,
    ) -> Result<Vec<i64>> {
        let batch_size = encoder_hidden_states.shape()[0];

        let mut generated_tokens = Vec::new();

        // 使用持久化的 KV cache（如果存在）
        let mut past_key_values = self.persistent_kv_cache.take();
        let mut current_seq_len = self.persistent_seq_len;

        // 初始decoder输入
        let mut decoder_input_ids = if past_key_values.is_none() {
            // 如果没有持久化的 KV cache，从头开始
            current_seq_len = 1; // 从 start token 开始
            Array2::from_elem((batch_size, 1), self.decoder_start_token_id)
        } else {
            // 如果有持久化的 KV cache，继续生成（使用占位符，实际解码器会使用 KV cache）
            current_seq_len += 1;
            Array2::from_elem((batch_size, 1), 0) // 占位符
        };

        for _ in 0..max_new_tokens {
            // 直接使用解码器推理（注意：encoder_hidden_states在这个模型中不需要显式传递）
            let outputs = self.decoder.forward(
                &decoder_input_ids,
                past_key_values.as_ref(),
            )?;

            // 获取下一个token
            let logits = &outputs.logits;
            let last_logits = logits.slice(s![0, -1, ..]).to_owned();

            // 应用温度
            let scaled_logits = if temperature != 1.0 {
                last_logits.mapv(|x| x / temperature)
            } else {
                last_logits
            };

            // 简单的贪心解码（选择概率最高的token）
            let next_token = scaled_logits
                .iter()
                .enumerate()
                .max_by(|(_, a), (_, b)| a.partial_cmp(b).unwrap())
                .map(|(i, _)| i as i64)
                .unwrap();

            // 检查是否结束
            if next_token == self.eos_token_id {
                break;
            }

            generated_tokens.push(next_token);

            // 更新decoder输入为下一个token
            decoder_input_ids = Array2::from_elem((batch_size, 1), next_token);

            // 更新KV缓存并应用窗口管理
            if let Some(new_kv) = outputs.past_key_values {
                current_seq_len += 1;
                past_key_values = Some(self.trim_kv_cache(new_kv, current_seq_len));

                // 如果使用了重置策略且 KV cache 被清空，重置序列长度
                if matches!(self.kv_cache_config.strategy, KvCacheStrategy::Reset)
                    && past_key_values.as_ref().map_or(true, |kv| kv.is_empty())
                {
                    current_seq_len = 1;
                    past_key_values = None;
                }
            }
        }

        // 保存持久化的 KV cache 和序列长度
        self.persistent_kv_cache = past_key_values;
        self.persistent_seq_len = current_seq_len;

        Ok(generated_tokens)
    }

    /// 获取tokenizer的引用
    pub fn tokenizer(&self) -> &Tokenizer {
        &self.tokenizer
    }

    /// 将token ID解码为文本
    pub fn decode_tokens(&self, tokens: &[i64]) -> Result<String> {
        let token_ids: Vec<u32> = tokens.iter().map(|&x| x as u32).collect();
        Ok(self
            .tokenizer
            .decode(&token_ids, true)
            .map_err(|e| anyhow::anyhow!("Tokenizer decode error: {}", e))?)
    }

    /// 获取音频特征
    pub fn get_audio_features(&mut self, mel: Array2<f32>) -> Result<Array3<f32>> {
        // 添加batch维度 [mel_bins, time_steps] -> [1, mel_bins, time_steps]
        let mel_with_batch = mel.insert_axis(ndarray::Axis(0));

        // 使用编码器进行前向推理
        let encoder_output = self.encoder.forward(&mel_with_batch)?;

        Ok(encoder_output.last_hidden_state)
    }

    /// 从音频数据生成mel特征 (使用candle的pcm_to_mel)
    pub fn audio_to_mel_features(
        audio: &[f32],
        _sample_rate: usize,
        mel_filters: &[f32],
        config: &Config,
    ) -> Result<Array2<f32>> {
        let mel = audio::pcm_to_mel(config, audio, mel_filters);
        let mel_len = mel.len();
        let n_mels = config.num_mel_bins;
        let n_frames = mel_len / n_mels;
        let mut mel_features = Array2::zeros((n_mels, n_frames));
        for i in 0..n_mels {
            for j in 0..n_frames {
                let idx = i * n_frames + j;
                if idx < mel.len() {
                    mel_features[[i, j]] = mel[idx];
                }
            }
        }
        Ok(mel_features)
    }

    /// 端到端的音频转录方法
    pub fn transcribe_audio(
        &mut self,
        audio: &[f32],
        sample_rate: usize,
        max_new_tokens: Option<usize>,
        temperature: Option<f32>,
    ) -> Result<String> {
        let mel_filters = get_mel_filters(self.config.num_mel_bins)?;
        let mel_features =
            Self::audio_to_mel_features(audio, sample_rate, &mel_filters, &self.config)?;
        let encoder_features = self.get_audio_features(mel_features)?;
        let tokens = self.generate(
            &encoder_features,
            max_new_tokens.unwrap_or(256),
            temperature.unwrap_or(0.0),
        )?;
        self.decode_tokens(&tokens)
    }

    pub fn transcribe_audio_streaming(
        &mut self,
        audio: &[f32],
        sample_rate: usize,
        max_new_tokens: Option<usize>,
        temperature: Option<f32>,
        reset_cache: bool,
    ) -> Result<String> {
        if reset_cache {
            self.clear_persistent_kv_cache();
        }
        let mel_filters = get_mel_filters(self.config.num_mel_bins)?;
        let mel_features =
            Self::audio_to_mel_features(audio, sample_rate, &mel_filters, &self.config)?;
        let encoder_features = self.get_audio_features(mel_features)?;
        let tokens = self.generate(
            &encoder_features,
            max_new_tokens.unwrap_or(256),
            temperature.unwrap_or(0.0),
        )?;
        self.decode_tokens(&tokens)
    }

    /// 裁剪 KV cache 根据窗口策略
    fn trim_kv_cache(
        &self,
        past_key_values: Vec<(Array4<f32>, Array4<f32>)>,
        current_seq_len: usize,
    ) -> Vec<(Array4<f32>, Array4<f32>)> {
        match self.kv_cache_config.strategy {
            KvCacheStrategy::Unlimited => {
                // 无限追加，不做任何裁剪
                past_key_values
            }
            KvCacheStrategy::Reset => {
                // 如果当前序列长度超过最大长度，完全清空 KV cache
                if current_seq_len >= self.kv_cache_config.max_length {
                    Vec::new()
                } else {
                    past_key_values
                }
            }
            KvCacheStrategy::SlidingWindow => {
                // 滑动窗口：如果超过最大长度，移除前面的部分
                if current_seq_len <= self.kv_cache_config.max_length {
                    return past_key_values;
                }

                let target_length =
                    self.kv_cache_config.max_length - self.kv_cache_config.sliding_step;
                let trim_count = current_seq_len - target_length;

                past_key_values
                    .into_iter()
                    .map(|(key, value)| {
                        // key/value 的形状通常是 [batch_size, num_heads, seq_len, head_dim]
                        // 我们需要在 seq_len 维度上裁剪
                        let key_shape = key.shape();
                        let value_shape = value.shape();

                        if key_shape.len() != 4 || value_shape.len() != 4 {
                            // 如果形状不符合预期，不做裁剪
                            return (key, value);
                        }

                        let seq_len = key_shape[2];
                        if seq_len <= trim_count {
                            // 如果序列长度小于等于要裁剪的数量，返回空的 tensor
                            let empty_key =
                                Array4::zeros((key_shape[0], key_shape[1], 0, key_shape[3]));
                            let empty_value =
                                Array4::zeros((value_shape[0], value_shape[1], 0, value_shape[3]));
                            return (empty_key, empty_value);
                        }

                        // 裁剪前 trim_count 个 tokens
                        let trimmed_key = key.slice(s![.., .., trim_count.., ..]).to_owned();
                        let trimmed_value = value.slice(s![.., .., trim_count.., ..]).to_owned();

                        (trimmed_key, trimmed_value)
                    })
                    .collect()
            }
        }
    }

    /// 清空持久化的 KV cache
    pub fn clear_persistent_kv_cache(&mut self) {
        self.persistent_kv_cache = None;
        self.persistent_seq_len = 0;
    }

    /// 检查是否有持久化的 KV cache
    pub fn has_persistent_kv_cache(&self) -> bool {
        self.persistent_kv_cache.is_some()
    }

    /// 获取当前持久化序列的长度
    pub fn get_persistent_seq_len(&self) -> usize {
        self.persistent_seq_len
    }

    /// 获取持久化 KV cache 的内存使用情况（估算，以字节为单位）
    pub fn get_kv_cache_memory_usage(&self) -> usize {
        if let Some(ref kv_cache) = self.persistent_kv_cache {
            kv_cache
                .iter()
                .map(|(key, value)| {
                    let key_size = key.len() * std::mem::size_of::<f32>();
                    let value_size = value.len() * std::mem::size_of::<f32>();
                    key_size + value_size
                })
                .sum()
        } else {
            0
        }
    }

    /// 设置新的 KV cache 配置并清空现有的持久化 cache
    pub fn update_kv_cache_config(&mut self, new_config: KvCacheConfig) {
        self.kv_cache_config = new_config;
        // 清空现有的 cache，因为配置已经改变
        self.clear_persistent_kv_cache();
    }
}

pub fn get_mel_filters(num_mel_bins: usize) -> Result<Vec<f32>> {
    let mel_bytes = crate::candle_models::whisper::get_mel_bytes(num_mel_bins)?;
    let mut mel_filters = vec![0f32; mel_bytes.len() / 4];
    use byteorder::{ByteOrder, LittleEndian};
    LittleEndian::read_f32_into(&mel_bytes, &mut mel_filters);
    Ok(mel_filters)
}

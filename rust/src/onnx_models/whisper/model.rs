use anyhow::Result;
use candle_transformers::models::whisper::{audio, Config};
use ndarray::{s, Array2, Array3};
use ort::{session::Session, value::Value};
use std::collections::HashMap;
use tokenizers::Tokenizer;

use crate::onnx_models::{find_model_path, init_model};

/// Whisper ONNX模型输出结构
#[derive(Debug, Clone)]
pub struct Seq2SeqLMOutput {
    pub logits: Array3<f32>, // [batch_size, sequence_length, vocab_size]
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
    session: Session,
}

impl ORTDecoderForSeq2Seq {
    pub fn new(decoder_path: &str, try_gpu: bool, _config: &Config) -> Result<Self> {
        let session = init_model(decoder_path.to_string(), try_gpu)?;
        Ok(Self { session })
    }

    /// 前向推理
    pub fn forward(
        &mut self,
        input_ids: &Array2<i64>,
        encoder_hidden_states: &Array3<f32>,
    ) -> Result<Seq2SeqLMOutput> {
        // 运行推理
        let outputs = self.session.run(ort::inputs![
            "input_ids" => Value::from_array(input_ids.clone())?,
            "encoder_hidden_states" => Value::from_array(encoder_hidden_states.clone())?
        ])?;

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

        Ok(Seq2SeqLMOutput { logits })
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
}

impl ORTModelForWhisper {
    pub fn new(
        models: &HashMap<String, String>,
        tokenizer: Tokenizer,
        config: Config,
        try_gpu: bool,
    ) -> Result<Self> {
        // 查找模型路径
        let encoder_path = find_model_path(models, Some("encoder"))
            .ok_or_else(|| anyhow::anyhow!("Encoder model not found"))?;

        let decoder_path = find_model_path(models, Some("decoder"))
            .ok_or_else(|| anyhow::anyhow!("Decoder model not found"))?;

        // 创建编码器和解码器
        let encoder = ORTEncoderForSpeech::new(&encoder_path, try_gpu)?;
        let decoder = ORTDecoderForSeq2Seq::new(&decoder_path, try_gpu, &config)?;

        // print all input output names
        let encoder_input_names = encoder.session.inputs.iter().clone();
        let encoder_output_names = encoder.session.outputs.iter().clone();
        println!("Encoder input names: {:?}", encoder_input_names);
        println!("Encoder output names: {:?}", encoder_output_names);
        let decoder_input_names = decoder.session.inputs.iter().clone();
        let decoder_output_names = decoder.session.outputs.iter().clone();
        println!("Decoder input names: {:?}", decoder_input_names);
        println!("Decoder output names: {:?}", decoder_output_names);

        Ok(Self {
            encoder,
            decoder,
            tokenizer,
            config,
            decoder_start_token_id: 50258,
            eos_token_id: 50257,
        })
    }

    /// 前向推理
    pub fn forward(
        &mut self,
        input_features: &Array3<f32>,
        decoder_input_ids: &Array2<i64>,
    ) -> Result<Seq2SeqLMOutput> {
        // 编码器推理
        let encoder_outputs = self.encoder.forward(input_features)?;

        // 解码器推理
        self.decoder.forward(
            decoder_input_ids,
            &encoder_outputs.last_hidden_state,
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

        // 构建初始序列，从 start token 开始
        let mut current_sequence = vec![self.decoder_start_token_id];

        for _ in 0..max_new_tokens {
            // 构建当前输入序列
            let decoder_input_ids = Array2::from_shape_vec(
                (batch_size, current_sequence.len()),
                current_sequence.repeat(batch_size),
            )?;

            // 解码器推理
            let outputs = self.decoder.forward(&decoder_input_ids, encoder_hidden_states)?;

            // 获取最后一个位置的 logits
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
            current_sequence.push(next_token);
        }

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
}

pub fn get_mel_filters(num_mel_bins: usize) -> Result<Vec<f32>> {
    let mel_bytes = crate::candle_models::whisper::get_mel_bytes(num_mel_bins)?;
    let mut mel_filters = vec![0f32; mel_bytes.len() / 4];
    use byteorder::{ByteOrder, LittleEndian};
    LittleEndian::read_f32_into(&mel_bytes, &mut mel_filters);
    Ok(mel_filters)
}

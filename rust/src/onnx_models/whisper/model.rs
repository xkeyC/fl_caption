use ndarray::{Array, Array1, Axis};
use ort::session::Session;
use std::time::Instant;

use crate::candle_models::whisper::model::{DecodingResult, Segment, WhisperStatus};

pub struct WhisperModel {
    session: Session,
    // 推理参数
    max_length: i32,
    min_length: i32,
    num_beams: i32,
    num_return_sequences: i32,
    length_penalty: f32,
    repetition_penalty: f32,
    // num_mel_bins: i32,
    // n_frames: i32,
    decoder_start_token_id: i32,
    predict_timestamps: bool,
}

impl WhisperModel {
    pub fn from_session(session: Session) -> anyhow::Result<Self> {
        println!("Whisper Model inputs:");
        for input in session.inputs.iter() {
            println!("  - name: {}, type: {:?}", input.name, input.input_type);
        }
        println!("Whisper Model outputs:");
        for output in session.outputs.iter() {
            println!("  - name: {}, type: {:?}", output.name, output.output_type);
        }

        // const values
        // https://github.com/microsoft/Olive/blob/d4d424f9b370e736e79b17487c037d5aad766315/examples/whisper/code/whisper_dataset.py#L11
        const SAMPLE_RATE: i32 = 16000;
        const HOP_LENGTH: i32 = 160;
        const CHUNK_LENGTH: i32 = 30;
        const N_SAMPLES: i32 = CHUNK_LENGTH * SAMPLE_RATE;
        const N_FRAMES: i32 = N_SAMPLES / HOP_LENGTH;

        // disable timestamps
        let predict_timestamps = false;

        // value from metadata
        let get_metadata_value = |key: &str, default: &str| -> String {
            session
                .metadata()
                .ok()
                .and_then(|metadata| metadata.custom(key).ok().flatten())
                .unwrap_or_else(|| default.to_string())
        };

        let max_length = get_metadata_value("max_length", "200")
            .parse::<i32>()
            .unwrap_or(200);
        let min_length = get_metadata_value("min_length", "0")
            .parse::<i32>()
            .unwrap_or(0);
        let num_beams = get_metadata_value("num_beams", "2")
            .parse::<i32>()
            .unwrap_or(2);
        let num_mel_bins = get_metadata_value("num_mel_bins", "80")
            .parse::<i32>()
            .unwrap_or(80);
        let num_return_sequences = get_metadata_value("num_return_sequences", "1")
            .parse::<i32>()
            .unwrap_or(1);
        let length_penalty = get_metadata_value("length_penalty", "1.0")
            .parse::<f32>()
            .unwrap_or(1.0);
        let repetition_penalty = get_metadata_value("repetition_penalty", "1.0")
            .parse::<f32>()
            .unwrap_or(1.0);
        let decoder_start_token_id = get_metadata_value("decoder_start_token_id", "50258")
            .parse::<i32>()
            .unwrap_or(50258);

        println!("Whisper model parameters loaded:");
        println!("  - max_length: {}", max_length);
        println!("  - min_length: {}", min_length);
        println!("  - num_beams: {}", num_beams);
        println!("  - num_return_sequences: {}", num_return_sequences);
        println!("  - length_penalty: {}", length_penalty);
        println!("  - repetition_penalty: {}", repetition_penalty);
        println!("  - num_mel_bins: {}", num_mel_bins);
        println!("  - n_frames: {}", N_FRAMES);
        println!("  - decoder_start_token_id: {}", decoder_start_token_id);
        println!("  - predict_timestamps: {}", predict_timestamps);

        Ok(Self {
            session,
            max_length,
            min_length,
            num_beams,
            num_return_sequences,
            length_penalty,
            repetition_penalty,
            // num_mel_bins,
            // n_frames: N_FRAMES,
            decoder_start_token_id,
            predict_timestamps,
        })
    }

    pub fn inference(
        &mut self,
        audio_data: &[f32],
        language: Option<&str>,
        task: Option<&str>, // "transcribe" 或 "translate"
    ) -> anyhow::Result<String> {
        use ort::value::Value;

        // 将音频数据转换为WAV格式
        let audio_bytes = self.convert_audio_to_wav(audio_data);
        let audio = Array1::from_iter(audio_bytes.iter().copied());
        let audio = audio.into_owned().insert_axis(Axis(0));

        // 使用模型属性中的参数
        let max_length = Array::from_shape_vec((1,), vec![self.max_length])?;
        let min_length = Array::from_shape_vec((1,), vec![self.min_length])?;
        let num_beams = Array::from_shape_vec((1,), vec![self.num_beams])?;
        let num_return_sequences = Array::from_shape_vec((1,), vec![self.num_return_sequences])?;
        let length_penalty = Array::from_shape_vec((1,), vec![self.length_penalty])?;
        let repetition_penalty = Array::from_shape_vec((1,), vec![self.repetition_penalty])?;

        // 构建 decoder_input_ids
        let language_token = self.language_to_token(language.unwrap_or("en"));

        let task_token = match task.unwrap_or("transcribe") {
            "translate" => 50358, // translate token
            _ => 50359,           // transcribe token (default)
        };

        let timestamp_token = if self.predict_timestamps {
            50364 // 启用时间戳
        } else {
            50363 // 不使用时间戳
        };

        // 构建强制解码器ID：[start_token, language_token, task_token, timestamp_token]
        let decoder_input_ids = Array::from_shape_vec(
            (1, 4),
            vec![
                self.decoder_start_token_id,
                language_token as i32,
                task_token,
                timestamp_token,
            ],
        )?;

        // 转换为 Value
        let audio_value = Value::from_array(audio)?;
        let max_length_value = Value::from_array(max_length)?;
        let min_length_value = Value::from_array(min_length)?;
        let num_beams_value = Value::from_array(num_beams)?;
        let num_return_sequences_value = Value::from_array(num_return_sequences)?;
        let length_penalty_value = Value::from_array(length_penalty)?;
        let repetition_penalty_value = Value::from_array(repetition_penalty)?;
        let decoder_input_ids_value = Value::from_array(decoder_input_ids)?;

        let start = Instant::now();

        // 使用 ort::inputs! 宏来正确构建输入
        let outputs = self.session.run(ort::inputs![
            "audio_stream" => audio_value,
            "max_length" => max_length_value,
            "min_length" => min_length_value,
            "num_beams" => num_beams_value,
            "num_return_sequences" => num_return_sequences_value,
            "length_penalty" => length_penalty_value,
            "repetition_penalty" => repetition_penalty_value,
            "decoder_input_ids" => decoder_input_ids_value,
        ])?;

        let inference_duration = start.elapsed();
        println!(
            "Whisper inference took {} seconds",
            inference_duration.as_secs_f32()
        );

        // 获取输出
        let output_keys: Vec<_> = outputs.keys().collect();
        println!("Available output keys: {:?}", output_keys);

        // 尝试获取字符串输出
        if let Some(str_output) = outputs.get("str") {
            println!("Found 'str' output, type: {:?}", str_output.dtype());
            println!("Output shape: {:?}", str_output.shape());

            // 使用 try_extract_string_array 提取字符串数组
            match str_output.try_extract_string_array() {
                Ok(string_array) => {
                    // 获取数组中的第一个字符串
                    if let Some(text) = string_array.iter().next() {
                        Ok(text.clone())
                    } else {
                        Ok("Empty string array".to_string())
                    }
                }
                Err(e) => {
                    println!("Failed to extract string array: {:?}", e);
                    Ok("Failed to extract string from model output".to_string())
                }
            }
        } else {
            Err(anyhow::anyhow!("No 'str' output found from model"))
        }
    }

    fn language_to_token(&self, language: &str) -> u32 {
        super::multilingual::get_token_id(language).unwrap_or(50259)
    }

    fn convert_audio_to_wav(&self, audio_data: &[f32]) -> Vec<u8> {
        let pcm_data: Vec<u8> = audio_data
            .iter()
            .flat_map(|&sample| {
                let sample_i16 = (sample.clamp(-1.0, 1.0) * 32767.0) as i16;
                sample_i16.to_le_bytes()
            })
            .collect();

        // WAV header
        let sample_rate = 16000u32;
        let num_channels = 1u16;
        let bits_per_sample = 16u16;
        let byte_rate = sample_rate * num_channels as u32 * bits_per_sample as u32 / 8;
        let block_align = num_channels * bits_per_sample / 8;
        let data_size = pcm_data.len() as u32;
        let file_size = 36 + data_size;

        let mut audio_bytes = Vec::new();

        // RIFF header
        audio_bytes.extend_from_slice(b"RIFF");
        audio_bytes.extend_from_slice(&file_size.to_le_bytes());
        audio_bytes.extend_from_slice(b"WAVE");

        // fmt chunk
        audio_bytes.extend_from_slice(b"fmt ");
        audio_bytes.extend_from_slice(&16u32.to_le_bytes()); // fmt chunk size
        audio_bytes.extend_from_slice(&1u16.to_le_bytes()); // audio format (PCM)
        audio_bytes.extend_from_slice(&num_channels.to_le_bytes());
        audio_bytes.extend_from_slice(&sample_rate.to_le_bytes());
        audio_bytes.extend_from_slice(&byte_rate.to_le_bytes());
        audio_bytes.extend_from_slice(&block_align.to_le_bytes());
        audio_bytes.extend_from_slice(&bits_per_sample.to_le_bytes());

        // data chunk
        audio_bytes.extend_from_slice(b"data");
        audio_bytes.extend_from_slice(&data_size.to_le_bytes());
        audio_bytes.extend_from_slice(&pcm_data);

        audio_bytes
    }
}

pub fn create_whisper_segment(
    text: String,
    audio_duration_secs: f64,
    inference_duration_ms: u128,
    language: Option<String>,
) -> Segment {
    Segment {
        start: 0.0,
        duration: audio_duration_secs,
        dr: DecodingResult {
            tokens: vec![],
            text,
            avg_logprob: 0.0,
            no_speech_prob: 0.0,
            temperature: 0.0,
            compression_ratio: 1.0,
        },
        reasoning_duration: Some(inference_duration_ms),
        reasoning_lang: language,
        audio_duration: Some((audio_duration_secs * 1000.0) as u128),
        status: WhisperStatus::Working,
    }
}

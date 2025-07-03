use base64;
use kaldi_fbank_rust::{FbankOptions, OnlineFbank};
use ndarray::{s, Array1, Array2, Array3, Array4, Axis};
use ort::session::Session;
use std::collections::HashMap;
use std::time::Duration;

use crate::audio_capture::{AudioCapture, AudioCaptureConfig, PlatformAudioCapture};
use crate::candle_models::whisper::{
    model::{DecodingResult, Segment, WhisperStatus},
    LaunchCaptionParams,
};
use crate::onnx_models;
use tokio::time::Instant;

pub struct OnnxWhisperModel {
    encoder: Session,
    decoder: Session,
    // Model metadata
    n_text_layer: i32,
    n_text_ctx: i32,
    n_text_state: i32,
    n_mels: i32,
    sot: i32,
    eot: i32,
    translate: i32,
    transcribe: i32,
    no_timestamps: i32,
    no_speech: i32,
    blank: i32,
    sot_sequence: Vec<i32>,
    all_language_tokens: Vec<i32>,
    all_language_codes: Vec<String>,
    lang2id: HashMap<String, i32>,
    id2lang: HashMap<i32, String>,
    is_multilingual: bool,
    token_table: HashMap<i32, String>,
}

impl OnnxWhisperModel {
    pub fn new(encoder: Session, decoder: Session, tokenizer_data: &[u8]) -> anyhow::Result<Self> {
        // Load token table from tokenizer data - 按照Python代码实现
        let token_table = Self::load_token_table_from_data(tokenizer_data)?;

        // Create the model instance first
        let mut model = Self {
            encoder,
            decoder,
            n_text_layer: 12,
            n_text_ctx: 448,
            n_text_state: 768,
            n_mels: 80,
            sot: 50258,
            eot: 50257,
            translate: 50358,
            transcribe: 50359,
            no_timestamps: 50363,
            no_speech: 50362,
            blank: 220,
            sot_sequence: vec![50258, 50363],
            all_language_tokens: Vec::new(),
            all_language_codes: Vec::new(),
            lang2id: HashMap::new(),
            id2lang: HashMap::new(),
            is_multilingual: false,
            token_table,
        };

        println!("encoder Model inputs:");
        for input in model.encoder.inputs.iter() {
            println!("  - name: {}, type: {:?}", input.name, input.input_type);
        }

        println!("encoder Model outputs:");
        for output in model.encoder.outputs.iter() {
            println!("  - name: {}, type: {:?}", output.name, output.output_type);
        }

        println!("decoder Model inputs:");
        for input in model.decoder.inputs.iter() {
            println!("  - name: {}, type: {:?}", input.name, input.input_type);
        }

        println!("decoder Model outputs:");
        for output in model.decoder.outputs.iter() {
            println!("  - name: {}, type: {:?}", output.name, output.output_type);
        }

        // read metadata and update the values
        if let Ok(meta) = model.encoder.metadata() {
            if let Ok(Some(n_text_layer_str)) = meta.custom("n_text_layer") {
                if let Ok(layer) = n_text_layer_str.parse::<i32>() {
                    model.n_text_layer = layer;
                }
            }
            if let Ok(Some(n_text_ctx_str)) = meta.custom("n_text_ctx") {
                if let Ok(ctx) = n_text_ctx_str.parse::<i32>() {
                    model.n_text_ctx = ctx;
                }
            }
            if let Ok(Some(n_text_state_str)) = meta.custom("n_text_state") {
                if let Ok(state) = n_text_state_str.parse::<i32>() {
                    model.n_text_state = state;
                }
            }
            if let Ok(Some(n_mels_str)) = meta.custom("n_mels") {
                if let Ok(mels) = n_mels_str.parse::<i32>() {
                    model.n_mels = mels;
                }
            }
            if let Ok(Some(sot_str)) = meta.custom("sot") {
                if let Ok(sot_val) = sot_str.parse::<i32>() {
                    model.sot = sot_val;
                }
            }
            if let Ok(Some(eot_str)) = meta.custom("eot") {
                if let Ok(eot_val) = eot_str.parse::<i32>() {
                    model.eot = eot_val;
                }
            }
            if let Ok(Some(translate_str)) = meta.custom("translate") {
                if let Ok(translate_val) = translate_str.parse::<i32>() {
                    model.translate = translate_val;
                }
            }
            if let Ok(Some(transcribe_str)) = meta.custom("transcribe") {
                if let Ok(transcribe_val) = transcribe_str.parse::<i32>() {
                    model.transcribe = transcribe_val;
                }
            }
            if let Ok(Some(no_timestamps_str)) = meta.custom("no_timestamps") {
                if let Ok(no_timestamps_val) = no_timestamps_str.parse::<i32>() {
                    model.no_timestamps = no_timestamps_val;
                }
            }
            if let Ok(Some(no_speech_str)) = meta.custom("no_speech") {
                if let Ok(no_speech_val) = no_speech_str.parse::<i32>() {
                    model.no_speech = no_speech_val;
                }
            }
            if let Ok(Some(blank_str)) = meta.custom("blank_id") {
                if let Ok(blank_val) = blank_str.parse::<i32>() {
                    model.blank = blank_val;
                }
            }

            let mut sot_sequence = vec![model.sot];
            if let Ok(Some(sot_sequence_str)) = meta.custom("sot_sequence") {
                let parsed_sequence: Vec<i32> = sot_sequence_str
                    .split(',')
                    .filter_map(|s| s.trim().parse().ok())
                    .collect();
                if !parsed_sequence.is_empty() {
                    sot_sequence = parsed_sequence;
                }
            }
            sot_sequence.push(model.no_timestamps);
            model.sot_sequence = sot_sequence;

            if let Ok(Some(all_language_tokens_str)) = meta.custom("all_language_tokens") {
                model.all_language_tokens = all_language_tokens_str
                    .split(',')
                    .filter_map(|s| s.trim().parse().ok())
                    .collect();
            }

            if let Ok(Some(all_language_codes_str)) = meta.custom("all_language_codes") {
                model.all_language_codes = all_language_codes_str
                    .split(',')
                    .map(|s| s.trim().to_string())
                    .collect();
            }

            // Build language mappings
            for (code, &token) in model
                .all_language_codes
                .iter()
                .zip(model.all_language_tokens.iter())
            {
                model.lang2id.insert(code.clone(), token);
                model.id2lang.insert(token, code.clone());
            }

            if let Ok(Some(is_multilingual_str)) = meta.custom("is_multilingual") {
                if let Ok(multilingual_val) = is_multilingual_str.parse::<i32>() {
                    model.is_multilingual = multilingual_val == 1;
                }
            }
        }

        println!("ONNX Whisper model loaded:");
        println!("  - n_text_layer: {}", model.n_text_layer);
        println!("  - n_text_ctx: {}", model.n_text_ctx);
        println!("  - n_text_state: {}", model.n_text_state);
        println!("  - n_mels: {}", model.n_mels);
        println!("  - is_multilingual: {}", model.is_multilingual);
        println!("  - sot_sequence: {:?}", model.sot_sequence);

        Ok(model)
    }

    fn load_token_table_from_data(tokenizer_data: &[u8]) -> anyhow::Result<HashMap<i32, String>> {
        // 按照 Python 代码: load_tokens(args.tokens) 的方式实现
        // 假设 tokenizer_data 包含类似于 tokens 文件的内容
        let mut token_table = HashMap::new();
        let data_str = std::str::from_utf8(tokenizer_data)?;

        for (index, line) in data_str.lines().enumerate() {
            if let Some(token) = line.split_whitespace().next() {
                token_table.insert(index as i32, token.to_string());
            }
        }

        Ok(token_table)
    }

    pub fn run_encoder(&mut self, mel: &Array3<f32>) -> anyhow::Result<(Array4<f32>, Array4<f32>)> {
        use ort::value::Value;

        let mel_value = Value::from_array(mel.clone())?;

        let outputs = self.encoder.run(ort::inputs!["mel" => mel_value])?;

        let n_layer_cross_k = outputs
            .get("n_layer_cross_k")
            .ok_or_else(|| anyhow::anyhow!("Cannot find encoder output n_layer_cross_k"))?;

        let n_layer_cross_v = outputs
            .get("n_layer_cross_v")
            .ok_or_else(|| anyhow::anyhow!("Cannot find encoder output n_layer_cross_v"))?;

        // Extract tensor data
        let (k_shape, k_data) = n_layer_cross_k.try_extract_tensor::<f32>()?;
        let (v_shape, v_data) = n_layer_cross_v.try_extract_tensor::<f32>()?;

        // Convert to ndarray
        let k_array = Array4::from_shape_vec(
            (
                k_shape[0] as usize,
                k_shape[1] as usize,
                k_shape[2] as usize,
                k_shape[3] as usize,
            ),
            k_data.to_vec(),
        )?;
        let v_array = Array4::from_shape_vec(
            (
                v_shape[0] as usize,
                v_shape[1] as usize,
                v_shape[2] as usize,
                v_shape[3] as usize,
            ),
            v_data.to_vec(),
        )?;

        Ok((k_array, v_array))
    }

    pub fn run_decoder(
        &mut self,
        tokens: &Array2<i64>,
        n_layer_self_k_cache: &Array4<f32>,
        n_layer_self_v_cache: &Array4<f32>,
        n_layer_cross_k: &Array4<f32>,
        n_layer_cross_v: &Array4<f32>,
        offset: &Array1<i64>,
    ) -> anyhow::Result<(Array3<f32>, Array4<f32>, Array4<f32>)> {
        use ort::value::Value;

        let tokens_value = Value::from_array(tokens.clone())?;
        let k_cache_value = Value::from_array(n_layer_self_k_cache.clone())?;
        let v_cache_value = Value::from_array(n_layer_self_v_cache.clone())?;
        let cross_k_value = Value::from_array(n_layer_cross_k.clone())?;
        let cross_v_value = Value::from_array(n_layer_cross_v.clone())?;
        let offset_value = Value::from_array(offset.clone())?;

        let outputs = self.decoder.run(ort::inputs![
            "tokens" => tokens_value,
            "in_n_layer_self_k_cache" => k_cache_value,
            "in_n_layer_self_v_cache" => v_cache_value,
            "n_layer_cross_k" => cross_k_value,
            "n_layer_cross_v" => cross_v_value,
            "offset" => offset_value,
        ])?;

        let logits = outputs
            .get("logits")
            .or_else(|| {
                let keys: Vec<_> = outputs.keys().collect();
                if !keys.is_empty() {
                    outputs.get(&keys[0])
                } else {
                    None
                }
            })
            .ok_or_else(|| anyhow::anyhow!("Cannot find decoder output logits"))?;

        let out_k_cache = outputs
            .get("out_n_layer_self_k_cache")
            .or_else(|| {
                let keys: Vec<_> = outputs.keys().collect();
                if keys.len() > 1 {
                    outputs.get(&keys[1])
                } else {
                    None
                }
            })
            .ok_or_else(|| anyhow::anyhow!("Cannot find decoder output k_cache"))?;

        let out_v_cache = outputs
            .get("out_n_layer_self_v_cache")
            .or_else(|| {
                let keys: Vec<_> = outputs.keys().collect();
                if keys.len() > 2 {
                    outputs.get(&keys[2])
                } else {
                    None
                }
            })
            .ok_or_else(|| anyhow::anyhow!("Cannot find decoder output v_cache"))?;

        // Extract tensor data
        let (logits_shape, logits_data) = logits.try_extract_tensor::<f32>()?;
        let (k_cache_shape, k_cache_data) = out_k_cache.try_extract_tensor::<f32>()?;
        let (v_cache_shape, v_cache_data) = out_v_cache.try_extract_tensor::<f32>()?;

        // Convert to ndarray
        let logits_array = Array3::from_shape_vec(
            (
                logits_shape[0] as usize,
                logits_shape[1] as usize,
                logits_shape[2] as usize,
            ),
            logits_data.to_vec(),
        )?;
        let k_cache_array = Array4::from_shape_vec(
            (
                k_cache_shape[0] as usize,
                k_cache_shape[1] as usize,
                k_cache_shape[2] as usize,
                k_cache_shape[3] as usize,
            ),
            k_cache_data.to_vec(),
        )?;
        let v_cache_array = Array4::from_shape_vec(
            (
                v_cache_shape[0] as usize,
                v_cache_shape[1] as usize,
                v_cache_shape[2] as usize,
                v_cache_shape[3] as usize,
            ),
            v_cache_data.to_vec(),
        )?;

        Ok((logits_array, k_cache_array, v_cache_array))
    }

    pub fn get_self_cache(&self) -> (Array4<f32>, Array4<f32>) {
        let batch_size = 1;
        // Initialize cache with proper shape - use n_text_ctx for sequence dimension
        let n_layer_self_k_cache = Array4::zeros((
            self.n_text_layer as usize,
            batch_size,
            self.n_text_ctx as usize,
            self.n_text_state as usize,
        ));
        let n_layer_self_v_cache = Array4::zeros((
            self.n_text_layer as usize,
            batch_size,
            self.n_text_ctx as usize,
            self.n_text_state as usize,
        ));
        (n_layer_self_k_cache, n_layer_self_v_cache)
    }

    pub fn suppress_tokens(&self, logits: &mut Array1<f32>, is_initial: bool) {
        if is_initial {
            logits[self.eot as usize] = f32::NEG_INFINITY;
            logits[self.blank as usize] = f32::NEG_INFINITY;
        }

        logits[self.no_timestamps as usize] = f32::NEG_INFINITY;
        logits[self.sot as usize] = f32::NEG_INFINITY;
        logits[self.no_speech as usize] = f32::NEG_INFINITY;
        logits[self.translate as usize] = f32::NEG_INFINITY;
    }

    pub fn detect_language(
        &mut self,
        n_layer_cross_k: &Array4<f32>,
        n_layer_cross_v: &Array4<f32>,
    ) -> anyhow::Result<i32> {
        let tokens = Array2::from_shape_vec((1, 1), vec![self.sot as i64])?;
        let offset = Array1::from_vec(vec![0i64]);
        let (n_layer_self_k_cache, n_layer_self_v_cache) = self.get_self_cache();

        let (logits, _, _) = self.run_decoder(
            &tokens,
            &n_layer_self_k_cache,
            &n_layer_self_v_cache,
            n_layer_cross_k,
            n_layer_cross_v,
            &offset,
        )?;

        let mut logits_1d = logits.slice(s![0, 0, ..]).to_owned();

        // Mask out non-language tokens
        for i in 0..logits_1d.len() {
            if !self.all_language_tokens.contains(&(i as i32)) {
                logits_1d[i] = f32::NEG_INFINITY;
            }
        }

        let lang_id = logits_1d
            .iter()
            .enumerate()
            .max_by(|(_, a), (_, b)| a.partial_cmp(b).unwrap())
            .map(|(i, _)| i as i32)
            .unwrap_or(0);

        if let Some(lang_code) = self.id2lang.get(&lang_id) {
            println!("Detected language: {}", lang_code);
        }

        Ok(lang_id)
    }

    pub fn decode_tokens(&self, tokens: &[i32]) -> String {
        // 按照 Python 代码的实现：
        // s = b""
        // for i in results:
        //     if i in token_table:
        //         s += base64.b64decode(token_table[i])
        // print(s.decode().strip())

        use base64::prelude::*;
        let mut result_bytes = Vec::new();

        for &token in tokens {
            if let Some(token_str) = self.token_table.get(&token) {
                // Try to decode as base64
                if let Ok(decoded) = BASE64_STANDARD.decode(token_str) {
                    result_bytes.extend_from_slice(&decoded);
                } else {
                    // If base64 decode fails, use the token string as bytes
                    result_bytes.extend_from_slice(token_str.as_bytes());
                }
            }
        }

        String::from_utf8_lossy(&result_bytes).trim().to_string()
    }
}

fn compute_features(samples: &[f32], sample_rate: f32, n_mels: i32) -> anyhow::Result<Array3<f32>> {
    let mut fbank_opts = FbankOptions::default();
    fbank_opts.frame_opts.dither = 0.0;
    fbank_opts.frame_opts.snip_edges = false;
    fbank_opts.frame_opts.samp_freq = sample_rate;
    fbank_opts.frame_opts.window_type = std::ffi::CStr::from_bytes_with_nul(b"hann\0")
        .unwrap()
        .as_ptr();
    fbank_opts.mel_opts.num_bins = n_mels;

    let mut online_fbank = OnlineFbank::new(fbank_opts);

    // Scale samples to 16-bit range
    let scaled_samples: Vec<f32> = samples.iter().map(|&x| x * 32768.0).collect();
    online_fbank.accept_waveform(sample_rate, &scaled_samples);
    online_fbank.input_finished();

    let num_frames = online_fbank.num_ready_frames();
    if num_frames == 0 {
        return Err(anyhow::anyhow!("No frames ready"));
    }

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

    // Apply log and normalization like Whisper
    let log_spec = feature_matrix.mapv(|x| (x.max(1e-10)).log10());
    let log_spec_max = log_spec.fold(f32::NEG_INFINITY, |acc, &x| acc.max(x));
    let log_spec = log_spec.mapv(|x| x.max(log_spec_max - 8.0));
    let mel = (log_spec + 4.0) / 4.0;

    // Pad to ensure we can detect end of transcription
    let target_frames = 3000;
    let current_frames = mel.shape()[0];
    let padded_frames = if current_frames < target_frames {
        target_frames
    } else {
        current_frames + 1500 // Add some padding for eot detection
    };

    let mut padded_mel = Array2::zeros((padded_frames, feature_dim));
    let copy_frames = current_frames.min(target_frames - 50);
    padded_mel
        .slice_mut(s![..copy_frames, ..])
        .assign(&mel.slice(s![..copy_frames, ..]));

    // Transpose and add batch dimension: (T, n_mels) -> (1, n_mels, T)
    let mel_transposed = padded_mel.t().to_owned();
    let mel_batched = mel_transposed.insert_axis(Axis(0));

    Ok(mel_batched)
}

pub async fn launch_caption<F>(
    encoder_session: Session,
    decoder_session: Session,
    params: LaunchCaptionParams,
    mut result_callback: F,
) -> anyhow::Result<()>
where
    F: FnMut(Vec<Segment>) + Send + 'static,
{
    let LaunchCaptionParams {
        tokenizer_data,
        audio_device,
        audio_device_is_input,
        audio_language,
        is_multilingual,
        cancel_token,
        inference_timeout,
        inference_interval_ms,
        whisper_max_audio_duration,
        vad_model_path,
        vad_filters_value,
        ..
    } = params;

    result_callback(_make_status_response(WhisperStatus::Loading));

    // Initialize ONNX Whisper model
    let mut model = OnnxWhisperModel::new(encoder_session, decoder_session, &tokenizer_data)?;

    // Set up audio capture
    let audio_capture_config = AudioCaptureConfig {
        device: audio_device,
        is_input: audio_device_is_input.unwrap_or(true),
        target_sample_rate: 16000,
        target_channels: 1,
    };

    let audio_capture = PlatformAudioCapture::new(audio_capture_config)?;
    let audio_info = audio_capture.get_info();
    println!("ONNX Whisper Audio capture info: {:?}", audio_info);

    let rx = audio_capture.start_capture(cancel_token.child_token())?;

    result_callback(_make_status_response(WhisperStatus::Ready));
    println!("ONNX Whisper Ready...");

    // Audio processing state
    let mut buffered_pcm = vec![];
    let mut history_pcm = Vec::new();
    let mut last_inference_time = Instant::now();
    let mut first_inference_done = false;
    let inference_interval = Duration::from_millis(inference_interval_ms.unwrap_or(2000));
    let max_audio_duration: usize = whisper_max_audio_duration.unwrap_or(12) as usize;
    let mut language_detected = false;
    let mut language_token = None;

    // VAD model
    let mut vad_model = if let Some(vad_model_path) = vad_model_path {
        let model = onnx_models::vad::new_vad_model(vad_model_path, false);
        if let Ok(model) = model {
            Some(model)
        } else {
            println!("Failed to load VAD model: {:?}", model.err().unwrap());
            None
        }
    } else {
        None
    };

    println!("Starting ONNX Whisper audio processing loop...");
    let mut debug_counter = 0;

    while !cancel_token.is_cancelled() {
        debug_counter += 1;
        if debug_counter % 500 == 0 {
            println!(
                "ONNX Whisper Audio processing loop iteration {}, buffered_pcm.len(): {}",
                debug_counter,
                buffered_pcm.len()
            );
        }

        // Receive audio data
        let pcm = rx.recv_timeout(Duration::from_millis(100));

        if pcm.is_err() {
            let err = pcm.unwrap_err();
            if debug_counter % 1000 == 0 {
                println!(
                    "ONNX Whisper Audio recv timeout or error: {:?}, cancel_token cancelled: {}",
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
        buffered_pcm.extend_from_slice(&pcm);

        // Wait for initial data
        if !first_inference_done {
            if buffered_pcm.len() < 3 * 16000 {
                continue;
            }
            first_inference_done = true;
        }

        // Check inference interval
        let now = Instant::now();
        if now.duration_since(last_inference_time) < inference_interval {
            continue;
        }

        let inference_start = Instant::now();

        // VAD check
        if let Some(vad_model) = vad_model.as_mut() {
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
                } else {
                    buffered_pcm.clear();
                    last_inference_time = Instant::now();
                    continue;
                }
            }
        }

        // Audio length management
        let max_samples = max_audio_duration * 16000;
        let total_len = history_pcm.len() + buffered_pcm.len();

        let mut adjusted_history_pcm = history_pcm.clone();
        if total_len > max_samples {
            let excess = total_len - max_samples;
            if history_pcm.len() > excess {
                adjusted_history_pcm = history_pcm[excess..].to_vec();
            } else {
                adjusted_history_pcm = Vec::new();
            }
        }

        // Combine audio data
        let mut combined_pcm = Vec::with_capacity(adjusted_history_pcm.len() + buffered_pcm.len());
        combined_pcm.extend_from_slice(&adjusted_history_pcm);
        combined_pcm.extend_from_slice(&buffered_pcm);

        history_pcm = combined_pcm.clone();
        buffered_pcm.clear();

        // Run ONNX Whisper inference
        match run_onnx_whisper_inference(
            &mut model,
            &combined_pcm,
            &audio_language,
            is_multilingual.unwrap_or(false),
            &mut language_detected,
            &mut language_token,
            inference_timeout.or(Some(inference_interval)),
        ) {
            Ok(segments) => {
                let inference_duration = inference_start.elapsed();
                let audio_duration = (combined_pcm.len() as f32 / 16000.0 * 1000.0) as u128;

                let mut result_segments = segments;
                for segment in &mut result_segments {
                    segment.reasoning_duration = Some(inference_duration.as_millis());
                    segment.audio_duration = Some(audio_duration);
                }

                result_callback(result_segments);
            }
            Err(e) => {
                println!("ONNX Whisper inference error: {:?}", e);
                result_callback(_make_status_response(WhisperStatus::Error));
            }
        }

        last_inference_time = now;
    }

    println!("ONNX Whisper transcription cancelled");
    result_callback(_make_status_response(WhisperStatus::Exit));
    println!("ONNX Whisper Exit");
    Ok(())
}

fn run_onnx_whisper_inference(
    model: &mut OnnxWhisperModel,
    pcm: &[f32],
    audio_language: &Option<String>,
    _is_multilingual: bool,
    language_detected: &mut bool,
    language_token: &mut Option<i32>,
    #[allow(unused_variables)] timeout: Option<Duration>,
) -> anyhow::Result<Vec<Segment>> {
    // Compute mel features
    let mel = compute_features(pcm, 16000.0, model.n_mels)?;

    // Run encoder
    let (n_layer_cross_k, n_layer_cross_v) = model.run_encoder(&mel)?;

    // Language detection/setting
    if !*language_detected {
        if let Some(lang) = audio_language {
            if model.is_multilingual && model.lang2id.contains_key(lang) {
                *language_token = model.lang2id.get(lang).copied();
                if let Some(token) = language_token {
                    if model.sot_sequence.len() > 1 {
                        model.sot_sequence[1] = *token;
                    }
                }
            } else if !model.is_multilingual && lang != "en" {
                println!("This model supports only English. Given: {}", lang);
                return Ok(vec![]);
            }
        } else if model.is_multilingual {
            let detected_lang = model.detect_language(&n_layer_cross_k, &n_layer_cross_v)?;
            *language_token = Some(detected_lang);
            if model.sot_sequence.len() > 1 {
                model.sot_sequence[1] = detected_lang;
            }
        }
        *language_detected = true;
    }

    let (mut n_layer_self_k_cache, mut n_layer_self_v_cache) = model.get_self_cache();

    println!("Using sot_sequence: {:?}", model.sot_sequence);
    println!(
        "Initial cache shapes - K: {:?}, V: {:?}",
        n_layer_self_k_cache.shape(),
        n_layer_self_v_cache.shape()
    );
    println!(
        "Cross cache shapes - K: {:?}, V: {:?}",
        n_layer_cross_k.shape(),
        n_layer_cross_v.shape()
    );

    let tokens = Array2::from_shape_vec(
        (1, model.sot_sequence.len()),
        model.sot_sequence.iter().map(|&x| x as i64).collect(),
    )?;
    let mut offset = Array1::from_vec(vec![0i64]);

    println!(
        "Initial tokens shape: {:?}, offset: {:?}",
        tokens.shape(),
        offset
    );

    // Check if initial sequence would exceed context
    if model.sot_sequence.len() as i64 > model.n_text_ctx as i64 {
        return Err(anyhow::anyhow!(
            "SOT sequence length {} exceeds context limit {}",
            model.sot_sequence.len(),
            model.n_text_ctx
        ));
    }

    let (logits, new_k_cache, new_v_cache) = model.run_decoder(
        &tokens,
        &n_layer_self_k_cache,
        &n_layer_self_v_cache,
        &n_layer_cross_k,
        &n_layer_cross_v,
        &offset,
    )?;

    println!(
        "After first decoder run - logits shape: {:?}",
        logits.shape()
    );
    println!(
        "New cache shapes - K: {:?}, V: {:?}",
        new_k_cache.shape(),
        new_v_cache.shape()
    );

    n_layer_self_k_cache = new_k_cache;
    n_layer_self_v_cache = new_v_cache;
    offset[0] += model.sot_sequence.len() as i64;

    // logits.shape (batch_size, tokens.shape[1], vocab_size)
    // logits = logits[0, -1]
    let mut logits_last = logits.slice(s![0, -1, ..]).to_owned();
    model.suppress_tokens(&mut logits_last, true);

    // for greedy search, we don't need to compute softmax or log_softmax
    // max_token_id = logits.argmax(dim=-1)
    let mut max_token_id = logits_last
        .iter()
        .enumerate()
        .max_by(|(_, a), (_, b)| a.partial_cmp(b).unwrap())
        .map(|(i, _)| i as i32)
        .unwrap_or(0);

    let mut results = Vec::new();

    // for i in range(model.n_text_ctx):
    let max_steps = (model.n_text_ctx as i64 - offset[0]).max(0) as usize;
    for i in 0..max_steps {
        if max_token_id == model.eot {
            println!("Reached EOT token at step {}", i);
            break;
        }

        // Check if we've reached the context limit
        if offset[0] >= model.n_text_ctx as i64 {
            println!("Reached context limit at step {}, offset: {}", i, offset[0]);
            break;
        }

        // results.append(max_token_id.item())
        results.push(max_token_id);

        // tokens = torch.tensor([[results[-1]]])
        let tokens = Array2::from_shape_vec((1, 1), vec![max_token_id as i64])?;

        if i % 50 == 0 || i < 5 {
            // Reduce debug output
            println!(
                "Step {}: token_id={}, offset: {}",
                i, max_token_id, offset[0]
            );
        }

        let (logits, new_k_cache, new_v_cache) = model.run_decoder(
            &tokens,
            &n_layer_self_k_cache,
            &n_layer_self_v_cache,
            &n_layer_cross_k,
            &n_layer_cross_v,
            &offset,
        )?;

        n_layer_self_k_cache = new_k_cache;
        n_layer_self_v_cache = new_v_cache;
        offset[0] += 1;

        // logits = logits[0, -1]
        let mut logits_last = logits.slice(s![0, -1, ..]).to_owned();
        model.suppress_tokens(&mut logits_last, false);

        // max_token_id = logits.argmax(dim=-1)
        max_token_id = logits_last
            .iter()
            .enumerate()
            .max_by(|(_, a), (_, b)| a.partial_cmp(b).unwrap())
            .map(|(i, _)| i as i32)
            .unwrap_or(0);
    }

    // Decode tokens to text
    let text = model.decode_tokens(&results);

    let duration = pcm.len() as f64 / 16000.0;
    let segment = Segment {
        start: 0.0,
        duration,
        dr: DecodingResult {
            tokens: results.iter().map(|&t| t as u32).collect(),
            text,
            avg_logprob: 0.0,
            no_speech_prob: 0.0,
            temperature: 0.0,
            compression_ratio: 1.0,
        },
        reasoning_duration: None,
        reasoning_lang: language_token.and_then(|t| model.id2lang.get(&t).cloned()),
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

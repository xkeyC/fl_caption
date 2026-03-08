use crate::audio_capture::{AudioCapture, AudioCaptureConfig, PlatformAudioCapture};
use crate::audio_models;
use crate::frb_generated::StreamSink;
use once_cell::sync::Lazy;
use std::collections::HashMap;
use std::collections::VecDeque;
use std::sync::Mutex;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Instant;
use uuid::Uuid;

pub type CancellationToken = tokio_util::sync::CancellationToken;

static TOKEN_STORE: Lazy<Mutex<HashMap<String, CancellationToken>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));

static ASR_INITIALIZED: Lazy<Mutex<bool>> = Lazy::new(|| Mutex::new(false));
static ASR_MODEL_PATH: Lazy<Mutex<Option<String>>> = Lazy::new(|| Mutex::new(None));

pub fn create_cancellation_token() -> String {
    let token = CancellationToken::new();
    let uuid = Uuid::new_v4().to_string();

    if let Ok(mut store) = TOKEN_STORE.lock() {
        store.insert(uuid.clone(), token);
    }

    uuid
}

pub fn cancel_cancellation_token(token_id: String) {
    if let Ok(mut store) = TOKEN_STORE.lock() {
        if let Some(token) = store.remove(&token_id) {
            token.cancel();
        }
    }
}

pub struct WhisperClient {
    pub model_name: String,
    pub config: String,
    pub tokenizer: Vec<u8>,
    pub is_multilingual: bool,
    pub is_quantized: bool,
    pub model_type: String,
}

impl WhisperClient {
    pub fn new(
        model_name: String,
        config: String,
        tokenizer: Vec<u8>,
        is_multilingual: bool,
        is_quantized: bool,
        model_type: String,
    ) -> Self {
        Self {
            model_name,
            config,
            tokenizer,
            is_multilingual,
            is_quantized,
            model_type,
        }
    }
}

fn init_qwen_asr(
    model_path: Option<String>,
    forced_aligner_path: Option<String>,
    device: Option<String>,
    dtype: Option<String>,
    max_inference_batch_size: Option<i32>,
    max_new_tokens: Option<i32>,
) -> anyhow::Result<bool> {
    let stored_path = ASR_MODEL_PATH.lock().ok().and_then(|p| p.clone());
    let model_to_use = model_path.or(stored_path);
    
    let result = crate::python::init_qwen_asr(
        model_to_use.clone(),
        forced_aligner_path,
        device,
        dtype,
        max_inference_batch_size,
        max_new_tokens,
    ).map_err(|e| anyhow::anyhow!("Python error: {}", e))?;
    
    if result {
        if let Ok(mut initialized) = ASR_INITIALIZED.lock() {
            *initialized = true;
        }
        if let Ok(mut stored) = ASR_MODEL_PATH.lock() {
            *stored = model_to_use;
        }
    }
    
    Ok(result)
}

fn is_qwen_asr_initialized() -> bool {
    if let Ok(initialized) = ASR_INITIALIZED.lock() {
        *initialized
    } else {
        false
    }
}

pub async fn launch_caption(
    whisper_client: WhisperClient,
    stream_sink: StreamSink<Vec<audio_models::model::Segment>>,
    audio_device: Option<String>,
    audio_device_is_input: Option<bool>,
    audio_language: Option<String>,
    cancel_token_id: String,
    _with_timestamps: Option<bool>,
    _verbose: Option<bool>,
    _try_with_cuda: Option<bool>,
    whisper_max_audio_duration: Option<u32>,
    _inference_interval: Option<u64>,
    _whisper_default_max_decode_tokens: Option<usize>,
    _whisper_temperature: Option<f32>,
    vad_model_path: Option<String>,
    _vad_filters_value: Option<f32>,
) -> anyhow::Result<()> {
    let cancel_token = if let Ok(store) = TOKEN_STORE.lock() {
        store.get(&cancel_token_id).cloned()
    } else {
        None
    };
    
    println!("[launch_caption] Starting...");
    
    if !is_qwen_asr_initialized() {
        let model_name = if whisper_client.model_name.starts_with("Qwen") {
            whisper_client.model_name.clone()
        } else {
            "Qwen/Qwen3-ASR-0.6B".to_string()
        };
        
        println!("[launch_caption] Initializing Qwen ASR model: {} (from: {})", model_name, whisper_client.model_name);
        
        let forced_aligner_path = vad_model_path.clone()
            .unwrap_or_else(|| "Qwen/Qwen3-ForcedAligner-0.6B".to_string());
        
        init_qwen_asr(
            Some(model_name),
            Some(forced_aligner_path),
            Some("cuda:0".to_string()),
            Some("bfloat16".to_string()),
            Some(32),
            Some(128),
        )?;
        println!("[launch_caption] Qwen ASR model initialized");
    } else {
        println!("[launch_caption] Qwen ASR already initialized");
    }
    
    let audio_config = AudioCaptureConfig {
        device: audio_device,
        is_input: audio_device_is_input.unwrap_or(false),
        target_sample_rate: 16000,
        target_channels: 1,
    };
    
    let audio_capture = PlatformAudioCapture::new(audio_config)?;
    let audio_info = audio_capture.get_info();
    println!("[launch_caption] Audio device: {}, sample_rate: {}, channels: {}", 
        audio_info.device_name, audio_info.sample_rate, audio_info.channels);
    
    let child_token = if let Some(ref token) = cancel_token {
        token.child_token()
    } else {
        CancellationToken::new()
    };
    
    let mut audio_rx = audio_capture.start_capture(child_token.clone())?;
    
    let sr = 16000u32;
    let step_ms = 100u64;
    let buffer_sec = whisper_max_audio_duration.unwrap_or(5) as f64;
    let overlap_sec = buffer_sec / 2.0;
    
    let chunk_samples = (buffer_sec * sr as f64) as usize;
    let overlap_samples = (overlap_sec * sr as f64) as usize;
    
    println!("[launch_caption] Buffer: {}s ({} samples), Overlap: {}s ({} samples)", 
        buffer_sec, chunk_samples, overlap_sec, overlap_samples);
    
    let mut ring_buffer: VecDeque<f32> = VecDeque::with_capacity(chunk_samples * 2);
    let mut call_id: u32 = 0;
    let is_transcribing = Arc::new(AtomicBool::new(false));
    let last_transcribe_end_offset = Arc::new(std::sync::atomic::AtomicUsize::new(0));
    let last_context = Arc::new(std::sync::Mutex::new(String::new()));
    
    let result = async {
        let mut total_samples_received: usize = 0;
        
        loop {
            if child_token.is_cancelled() {
                println!("[launch_caption] Cancellation requested");
                break;
            }
            
            match tokio::time::timeout(std::time::Duration::from_millis(step_ms), audio_rx.recv()).await {
                Ok(Some(samples)) => {
                    let samples_len = samples.len();
                    ring_buffer.extend(samples);
                    total_samples_received += samples_len;
                    
                    let last_end = last_transcribe_end_offset.load(Ordering::Relaxed);
                    let available_for_transcribe = total_samples_received.saturating_sub(last_end);
                    
                    if available_for_transcribe >= chunk_samples && !is_transcribing.load(Ordering::Relaxed) {
                        let start_offset = last_end.saturating_sub(overlap_samples);
                        let end_offset = start_offset + chunk_samples;
                        
                        let buf_len = ring_buffer.len();
                        let total_overflow = total_samples_received.saturating_sub(buf_len);
                        
                        let chunk_start_idx = start_offset.saturating_sub(total_overflow);
                        let chunk_end_idx = end_offset.saturating_sub(total_overflow);
                        
                        if chunk_start_idx < buf_len && chunk_end_idx <= buf_len {
                            let chunk: Vec<f32> = ring_buffer.iter()
                                .skip(chunk_start_idx)
                                .take(chunk_end_idx - chunk_start_idx)
                                .copied()
                                .collect();
                            let chunk_len = chunk.len();
                            
                            if chunk_len >= chunk_samples / 2 {
                                call_id += 1;
                                let call_id_copy = call_id;
                                let lang = audio_language.clone();
                                let sink = stream_sink.clone();
                                let is_transcribing_clone = is_transcribing.clone();
                                let context_clone = last_context.clone();
                                
                                let context_for_transcribe = last_context.lock()
                                    .ok()
                                    .and_then(|ctx| {
                                        let s = ctx.clone();
                                        if s.is_empty() { None } else { Some(s) }
                                    });
                                
                                is_transcribing.store(true, Ordering::Relaxed);
                                last_transcribe_end_offset.store(end_offset, Ordering::Relaxed);
                                
                                println!("[launch_caption] Starting transcription {} (offset {}-{}, {} samples, context_len={})", 
                                    call_id_copy, start_offset, end_offset, chunk_len, 
                                    context_for_transcribe.as_ref().map(|s| s.len()).unwrap_or(0));
                                
                                tokio::task::spawn_blocking(move || {
                                    let start_time = Instant::now();
                                    let result = crate::python::transcribe_from_samples(
                                        chunk, sr, lang, context_for_transcribe, false
                                    );
                                    let inference_duration = start_time.elapsed().as_millis();
                                    is_transcribing_clone.store(false, Ordering::Relaxed);
                                    
                                    match result {
                                        Ok(res) => {
                                            println!("[launch_caption] Transcribe {} result: error={:?}, text_len={}, inference_time={}ms", 
                                                call_id_copy, res.error, res.text.len(), inference_duration);
                                            if res.error.is_none() && !res.text.is_empty() {
                                                let text = res.text.trim().to_string();
                                                println!("[call {:03}] inference={}ms language={} text={}", 
                                                    call_id_copy, inference_duration, res.language, text);
                                                
                                                if let Ok(mut ctx) = context_clone.lock() {
                                                    *ctx = text.clone();
                                                }
                                                
                                                let segment = audio_models::model::Segment {
                                                    start: 0.0,
                                                    duration: chunk_len as f64 / sr as f64,
                                                    dr: audio_models::model::DecodingResult {
                                                        tokens: vec![],
                                                        text,
                                                        avg_logprob: 0.0,
                                                        no_speech_prob: 0.0,
                                                        temperature: 0.0,
                                                        compression_ratio: 0.0,
                                                    },
                                                    reasoning_duration: Some(inference_duration),
                                                    reasoning_lang: Some(res.language),
                                                    audio_duration: Some((chunk_len as u128 * 1000) / sr as u128),
                                                    status: audio_models::model::WhisperStatus::Working,
                                                };
                                                
                                                if let Err(e) = sink.add(vec![segment]) {
                                                    println!("[launch_caption] Failed to send segment: {}", e);
                                                }
                                            }
                                        }
                                        Err(e) => {
                                            println!("[launch_caption] Transcribe {} error: {}", call_id_copy, e);
                                        }
                                    }
                                });
                            }
                        }
                    }
                    
                    if ring_buffer.len() > chunk_samples * 3 {
                        let drain_count = ring_buffer.len() - chunk_samples * 2;
                        for _ in 0..drain_count {
                            ring_buffer.pop_front();
                        }
                    }
                }
                Ok(None) => {
                    println!("[launch_caption] Audio channel closed");
                    break;
                }
                Err(_) => {
                    continue;
                }
            }
        }
        
        Ok::<(), anyhow::Error>(())
    }.await;
    
    if let Some(token) = cancel_token {
        token.cancelled().await;
    }
    
    result
}

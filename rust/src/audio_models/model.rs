#[derive(Debug, Clone)]
pub struct Segment {
    pub start: f64,
    pub duration: f64,
    pub dr: DecodingResult,
    pub reasoning_duration: Option<u128>,
    pub reasoning_lang: Option<String>,
    pub audio_duration: Option<u128>,
    pub status: WhisperStatus,
}

#[derive(Debug, Clone)]
pub struct DecodingResult {
    pub tokens: Vec<u32>,
    pub text: String,
    pub avg_logprob: f64,
    pub no_speech_prob: f64,
    pub temperature: f64,
    pub compression_ratio: f64,
}

#[derive(Debug, Clone)]
pub enum WhisperStatus {
    Loading,
    Ready,
    Error,
    Working,
    Exit,
}

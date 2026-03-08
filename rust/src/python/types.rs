#[derive(Debug, Clone)]
pub struct TranscriptionResult {
    pub language: String,
    pub text: String,
    pub time_stamps: Vec<TimeStamp>,
    pub error: Option<String>,
}

#[derive(Debug, Clone)]
pub struct TimeStamp {
    pub text: String,
    pub start_time: f64,
    pub end_time: f64,
}

impl Default for TranscriptionResult {
    fn default() -> Self {
        Self {
            language: String::new(),
            text: String::new(),
            time_stamps: Vec::new(),
            error: None,
        }
    }
}

//! Cuts a 16 kHz stream into utterances with Silero VAD (infra's port of
//! the reference `VADIterator`), keeping the audio of the utterance in
//! progress for partial recognition. An utterance longer than the maximum
//! is cut at its quietest window of the last seconds, so long speech with
//! no pause still produces captions in time.

use super::SAMPLE_RATE;
use anyhow::{anyhow, Result};
use local_adapter_silero_vad::{SileroVad, VadEvent, VadIterator, WINDOW};
use std::collections::VecDeque;
use std::path::Path;

#[derive(Debug, Clone, Copy)]
pub struct SegmenterConfig {
    pub threshold: f32,
    pub min_silence_ms: usize,
    pub speech_pad_ms: usize,
    pub max_segment_ms: usize,
    /// Shorter utterances (clicks, breaths) are dropped.
    pub min_segment_ms: usize,
}

impl SegmenterConfig {
    pub fn live() -> Self {
        Self {
            threshold: 0.5,
            min_silence_ms: 500,
            speech_pad_ms: 100,
            max_segment_ms: 12_000,
            min_segment_ms: 250,
        }
    }

    pub fn file() -> Self {
        Self {
            threshold: 0.5,
            min_silence_ms: 350,
            speech_pad_ms: 120,
            max_segment_ms: 15_000,
            min_segment_ms: 200,
        }
    }
}

#[derive(Debug, Clone)]
pub struct Utterance {
    /// Absolute sample positions since the stream began.
    pub start: usize,
    pub end: usize,
    pub samples: Vec<f32>,
}

pub struct Segmenter {
    vad: SileroVad,
    iterator: VadIterator,
    config: SegmenterConfig,
    pending: Vec<f32>,
    /// Audio from absolute sample `audio_start` on.
    audio: Vec<f32>,
    audio_start: usize,
    /// Samples given to the VAD (whole windows).
    fed: usize,
    current: Option<usize>,
    /// (window end, speech probability) of the recent windows.
    probabilities: VecDeque<(usize, f32)>,
    reset_after_speech: bool,
    reset_at: Option<usize>,
}

/// Audio kept before an utterance (the VAD's start padding reaches back).
const PRE_ROLL: usize = SAMPLE_RATE;
/// A forced cut looks for the quietest window this far back.
const CUT_SEARCH: usize = SAMPLE_RATE * 3;
/// ...but leaves at least this much in the utterance.
const CUT_MIN_KEEP: usize = SAMPLE_RATE * 2;
/// Silence after an utterance ends before the VAD state is reset.
const RESET_AFTER_SILENCE: usize = SAMPLE_RATE * 3 / 10;

impl Segmenter {
    pub fn new(model: &Path, config: SegmenterConfig) -> Result<Self> {
        let vad = SileroVad::load(model).map_err(|error| anyhow!("Silero VAD: {error}"))?;
        Ok(Self {
            vad,
            iterator: VadIterator::new(
                config.threshold,
                config.min_silence_ms,
                config.speech_pad_ms,
            ),
            config,
            pending: Vec::new(),
            audio: Vec::new(),
            audio_start: 0,
            fed: 0,
            current: None,
            probabilities: VecDeque::new(),
            reset_after_speech: std::env::var_os("FL_CAPTION_VAD_NO_RESET").is_none(),
            reset_at: None,
        })
    }

    /// Takes more audio; returns the utterances that ended.
    pub fn push(&mut self, input: &[f32]) -> Result<Vec<Utterance>> {
        self.audio.extend_from_slice(input);
        self.pending.extend_from_slice(input);
        let mut ended = Vec::new();
        let mut offset = 0;
        while self.pending.len() - offset >= WINDOW {
            let window = &self.pending[offset..offset + WINDOW];
            let probability = self
                .vad
                .probability(window)
                .map_err(|error| anyhow!("Silero VAD: {error}"))?;
            offset += WINDOW;
            self.fed += WINDOW;
            self.probabilities.push_back((self.fed, probability));
            while self
                .probabilities
                .front()
                .is_some_and(|(end, _)| self.fed - end > CUT_SEARCH + WINDOW)
            {
                self.probabilities.pop_front();
            }
            match self.iterator.step(probability) {
                Some(VadEvent::Start(start)) => {
                    self.current = Some(start.max(self.audio_start));
                }
                Some(VadEvent::End(end)) => {
                    if let Some(start) = self.current.take() {
                        ended.extend(self.cut(start, end.max(start)));
                    }
                    if self.reset_after_speech {
                        self.reset_at = Some(self.fed + RESET_AFTER_SILENCE);
                    }
                }
                None => {}
            }
            // After a longer silence the recurrent state, adapted to the
            // speaker who stopped, starts afresh: a much quieter speaker
            // next would go unheard. Short pauses keep it.
            if self.iterator.triggered() {
                self.reset_at = None;
            } else if self.reset_at.is_some_and(|at| self.fed >= at) {
                self.vad.reset();
                self.reset_at = None;
            }
            let max = self.config.max_segment_ms * SAMPLE_RATE / 1000;
            if let Some(start) = self.current {
                if self.fed - start > max {
                    let at = self.quietest_after(start + CUT_MIN_KEEP);
                    ended.extend(self.cut(start, at));
                    self.current = Some(at);
                }
            }
        }
        self.pending.drain(..offset);
        self.trim();
        Ok(ended)
    }

    /// The utterance still open, if speech is going on: its start and audio.
    pub fn ongoing(&self) -> Option<(usize, &[f32])> {
        let start = self.current?;
        let from = start.saturating_sub(self.audio_start);
        let to = (self.fed - self.audio_start).min(self.audio.len());
        (to > from).then(|| (start, &self.audio[from..to]))
    }

    /// Ends the stream: the open utterance, if any.
    pub fn finish(&mut self) -> Option<Utterance> {
        let start = self.current.take()?;
        let end = self.audio_start + self.audio.len();
        self.cut(start, end)
    }

    /// Clears all state (a new stream).
    pub fn reset(&mut self) {
        self.vad.reset();
        self.iterator = VadIterator::new(
            self.config.threshold,
            self.config.min_silence_ms,
            self.config.speech_pad_ms,
        );
        self.pending.clear();
        self.audio.clear();
        self.audio_start = 0;
        self.fed = 0;
        self.current = None;
        self.probabilities.clear();
        self.reset_at = None;
    }

    fn quietest_after(&self, earliest: usize) -> usize {
        self.probabilities
            .iter()
            .filter(|(end, _)| *end >= earliest)
            .min_by(|a, b| a.1.total_cmp(&b.1))
            .map(|(end, _)| end - WINDOW / 2)
            .unwrap_or(self.fed)
    }

    fn cut(&self, start: usize, end: usize) -> Option<Utterance> {
        let min = self.config.min_segment_ms * SAMPLE_RATE / 1000;
        if end <= start || end - start < min {
            return None;
        }
        let from = start.saturating_sub(self.audio_start);
        let to = end.saturating_sub(self.audio_start).min(self.audio.len());
        (to > from).then(|| Utterance {
            start,
            end,
            samples: self.audio[from..to].to_vec(),
        })
    }

    fn trim(&mut self) {
        let keep_from = self
            .current
            .unwrap_or(self.fed)
            .min(self.fed)
            .saturating_sub(PRE_ROLL);
        // Drain in steps of a second, not every call.
        if keep_from >= self.audio_start + SAMPLE_RATE {
            self.audio.drain(..keep_from - self.audio_start);
            self.audio_start = keep_from;
        }
    }
}

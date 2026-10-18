//! Live captions: capture → Silero VAD → ASR → translation.
//!
//! While someone speaks, the utterance so far is recognized every
//! `partial_interval_ms` (a partial caption, replaced as it grows); when the
//! VAD closes it, it is recognized once more (final) and translated with the
//! previous lines as context. Partials are translated too when asked for,
//! newest only: a newer partial or a final line stops a partial translation
//! in progress, while final lines are all translated, in order.

use super::asr::AsrOptions;
use super::capture::{self, SourceKind};
use super::catalog;
use super::lang;
use super::pool;
use super::segmenter::{Segmenter, SegmenterConfig, Utterance};
use super::text::{apply_replacements, Replacement};
use super::translate::{ApiClient, ApiConfig, Backend, PromptStyle, Translator, TranslatorConfig};
use super::{samples_to_ms, SAMPLE_RATE};
use anyhow::{anyhow, Result};
use std::collections::VecDeque;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::mpsc::RecvTimeoutError;
use std::sync::{Arc, Condvar, Mutex};
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

#[derive(Debug, Clone)]
pub enum BackendSetup {
    Local {
        model: String,
        gpu: bool,
        context: usize,
    },
    Api(ApiConfig),
}

#[derive(Debug, Clone)]
pub struct TranslationSetup {
    pub backend: BackendSetup,
    pub config: TranslatorConfig,
    pub translate_partials: bool,
    /// Lines the ASR heard in the target language are shown as they are.
    pub skip_same_language: bool,
}

#[derive(Debug, Clone)]
pub struct LiveConfig {
    pub asr_model: String,
    pub asr_gpu: bool,
    pub source: SourceKind,
    pub device: Option<String>,
    pub vad_model: PathBuf,
    pub segmenter: SegmenterConfig,
    pub partial_interval_ms: u64,
    /// Boost quiet input before the VAD and the recognizer.
    pub auto_gain: bool,
    pub asr_options: AsrOptions,
    pub replacements: Vec<Replacement>,
    pub translation: Option<TranslationSetup>,
    /// Plays this file into the pipeline at real-time pace instead of
    /// capturing (tests and demos).
    pub file_source: Option<PathBuf>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LiveState {
    Loading,
    Running,
    Stopped,
    Failed,
}

#[derive(Debug, Clone)]
pub enum LiveEvent {
    State {
        state: LiveState,
        message: String,
        asr_provider: String,
        device: String,
    },
    Level(f32),
    Partial {
        id: u64,
        text: String,
        start_ms: u64,
        /// Where the audio recognized for it ends.
        end_ms: u64,
        /// Leading characters the previous partial had too (LA-2): likely to
        /// stay; the rest may still change.
        stable_chars: usize,
        asr_ms: u64,
    },
    Final {
        id: u64,
        text: String,
        language: Option<String>,
        emotion: Option<String>,
        start_ms: u64,
        end_ms: u64,
        asr_ms: u64,
    },
    Translation {
        id: u64,
        text: String,
        partial: bool,
        done: bool,
        same_language: bool,
        first_token_ms: u64,
        total_ms: u64,
        prompt_tokens: usize,
        cached_tokens: usize,
    },
    Error(String),
}

pub type Emit = Arc<dyn Fn(LiveEvent) + Send + Sync>;

struct Tunables {
    asr_options: AsrOptions,
    replacements: Vec<Replacement>,
    skip_same_language: bool,
    translate_partials: bool,
}

struct Session {
    stop: Arc<AtomicBool>,
    thread: Option<JoinHandle<()>>,
    tunables: Arc<Mutex<Tunables>>,
    jobs: Option<Arc<Jobs>>,
}

static SESSION: Mutex<Option<Session>> = Mutex::new(None);

pub fn running() -> bool {
    SESSION
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .as_ref()
        .is_some_and(|session| session.thread.as_ref().is_some_and(|t| !t.is_finished()))
}

/// Starts captions (stopping a session already running).
pub fn start(config: LiveConfig, emit: Emit) {
    stop();
    let stop = Arc::new(AtomicBool::new(false));
    let tunables = Arc::new(Mutex::new(Tunables {
        asr_options: config.asr_options.clone(),
        replacements: config.replacements.clone(),
        skip_same_language: config
            .translation
            .as_ref()
            .is_some_and(|t| t.skip_same_language),
        translate_partials: config
            .translation
            .as_ref()
            .is_some_and(|t| t.translate_partials),
    }));
    let jobs = config
        .translation
        .as_ref()
        .map(|_| Arc::new(Jobs::default()));
    let thread = {
        let stop = stop.clone();
        let tunables = tunables.clone();
        let jobs = jobs.clone();
        std::thread::Builder::new()
            .name("fl-live".into())
            .spawn(move || {
                let result = run(config, emit.clone(), stop, tunables, jobs);
                let (state, message) = match result {
                    Ok(()) => (LiveState::Stopped, String::new()),
                    Err(error) => (LiveState::Failed, format!("{error:#}")),
                };
                emit(LiveEvent::State {
                    state,
                    message,
                    asr_provider: String::new(),
                    device: String::new(),
                });
            })
            .ok()
    };
    *SESSION.lock().unwrap_or_else(|e| e.into_inner()) = Some(Session {
        stop,
        thread,
        tunables,
        jobs,
    });
}

pub fn stop() {
    let session = SESSION.lock().unwrap_or_else(|e| e.into_inner()).take();
    if let Some(mut session) = session {
        session.stop.store(true, Ordering::Relaxed);
        if let Some(jobs) = &session.jobs {
            jobs.close();
        }
        if let Some(thread) = session.thread.take() {
            let _ = thread.join();
        }
    }
}

/// Changes the word lists and translation settings of the running session.
pub fn update(
    asr_options: AsrOptions,
    replacements: Vec<Replacement>,
    translation: Option<(TranslatorConfig, bool, bool)>,
) {
    let guard = SESSION.lock().unwrap_or_else(|e| e.into_inner());
    let Some(session) = guard.as_ref() else {
        return;
    };
    let mut tunables = session.tunables.lock().unwrap_or_else(|e| e.into_inner());
    tunables.asr_options = asr_options;
    tunables.replacements = replacements;
    if let Some((config, partials, skip_same)) = translation {
        tunables.translate_partials = partials;
        tunables.skip_same_language = skip_same;
        if let Some(jobs) = &session.jobs {
            jobs.set_config(config);
        }
    }
}

// ------------------------------------------------------------------ jobs

#[derive(Default)]
struct Queue {
    finals: VecDeque<(u64, String)>,
    partial: Option<(u64, String)>,
    config: Option<TranslatorConfig>,
    closed: bool,
}

#[derive(Default)]
struct Jobs {
    queue: Mutex<Queue>,
    ready: Condvar,
    /// Bumped on every new job: a partial translation stops when it moves.
    generation: AtomicU64,
}

enum Job {
    Final(u64, String),
    Partial(u64, String),
}

impl Jobs {
    fn push_final(&self, id: u64, text: String) {
        let mut queue = self.queue.lock().unwrap_or_else(|e| e.into_inner());
        queue.partial = None;
        queue.finals.push_back((id, text));
        self.generation.fetch_add(1, Ordering::SeqCst);
        self.ready.notify_one();
    }

    fn push_partial(&self, id: u64, text: String) {
        let mut queue = self.queue.lock().unwrap_or_else(|e| e.into_inner());
        queue.partial = Some((id, text));
        self.generation.fetch_add(1, Ordering::SeqCst);
        self.ready.notify_one();
    }

    fn set_config(&self, config: TranslatorConfig) {
        let mut queue = self.queue.lock().unwrap_or_else(|e| e.into_inner());
        queue.config = Some(config);
        self.ready.notify_one();
    }

    fn close(&self) {
        let mut queue = self.queue.lock().unwrap_or_else(|e| e.into_inner());
        queue.closed = true;
        self.generation.fetch_add(1, Ordering::SeqCst);
        self.ready.notify_all();
    }

    /// The next job (finals first), with the generation it started at; any
    /// config change to apply first. `None` once closed.
    fn next(&self) -> Option<(Option<TranslatorConfig>, Option<(Job, u64)>)> {
        let mut queue = self.queue.lock().unwrap_or_else(|e| e.into_inner());
        loop {
            if queue.closed {
                return None;
            }
            let config = queue.config.take();
            let job = if let Some((id, text)) = queue.finals.pop_front() {
                Some(Job::Final(id, text))
            } else {
                queue
                    .partial
                    .take()
                    .map(|(id, text)| Job::Partial(id, text))
            };
            if config.is_some() || job.is_some() {
                let generation = self.generation.load(Ordering::SeqCst);
                return Some((config, job.map(|job| (job, generation))));
            }
            queue = self.ready.wait(queue).unwrap_or_else(|e| e.into_inner());
        }
    }
}

fn make_translator(setup: &TranslationSetup) -> Result<Translator> {
    let backend = match &setup.backend {
        BackendSetup::Local {
            model,
            gpu,
            context,
        } => {
            let entry = catalog::find(model).ok_or_else(|| anyhow!("unknown model {model}"))?;
            Backend::Local {
                model: pool::chat(model, *gpu, *context)?,
                style: PromptStyle::for_engine(entry.engine),
            }
        }
        BackendSetup::Api(config) => Backend::Api(ApiClient::new(config.clone())?),
    };
    Ok(Translator::new(backend, setup.config.clone()))
}

fn translation_worker(mut translator: Translator, jobs: Arc<Jobs>, emit: Emit) {
    let mut last_partial = String::new();
    while let Some((config, job)) = jobs.next() {
        if let Some(config) = config {
            translator.set_config(config);
        }
        let Some((job, generation)) = job else {
            continue;
        };
        let (id, text, partial) = match job {
            Job::Final(id, text) => (id, text, false),
            Job::Partial(id, text) => {
                if text == last_partial {
                    continue;
                }
                last_partial = text.clone();
                (id, text, true)
            }
        };
        if !partial {
            last_partial.clear();
        }
        let emit_delta = emit.clone();
        let jobs_ref = jobs.clone();
        let result = translator.translate(&text, !partial, &mut |so_far| {
            if partial && jobs_ref.generation.load(Ordering::SeqCst) != generation {
                return false;
            }
            emit_delta(LiveEvent::Translation {
                id,
                text: so_far.to_string(),
                partial,
                done: false,
                same_language: false,
                first_token_ms: 0,
                total_ms: 0,
                prompt_tokens: 0,
                cached_tokens: 0,
            });
            true
        });
        match result {
            Ok(Some(done)) => emit(LiveEvent::Translation {
                id,
                text: done.text,
                partial,
                done: true,
                same_language: false,
                first_token_ms: done.first_token_ms,
                total_ms: done.total_ms,
                prompt_tokens: done.prompt_tokens,
                cached_tokens: done.cached_tokens,
            }),
            Ok(None) => {}
            Err(error) => emit(LiveEvent::Error(format!("translation: {error:#}"))),
        }
    }
}

// ------------------------------------------------------------------ main loop

/// Silence fed to the VAD when the device delivers nothing (WASAPI
/// loopback is silent while nothing plays), so an utterance still ends.
const GAP_FILL: Duration = Duration::from_millis(250);
/// Partials start once an utterance is this long.
const MIN_PARTIAL_SAMPLES: usize = SAMPLE_RATE * 6 / 10;

fn run(
    config: LiveConfig,
    emit: Emit,
    stop: Arc<AtomicBool>,
    tunables: Arc<Mutex<Tunables>>,
    jobs: Option<Arc<Jobs>>,
) -> Result<()> {
    let state = |state, message: &str, provider: &str, device: &str| {
        emit(LiveEvent::State {
            state,
            message: message.to_string(),
            asr_provider: provider.to_string(),
            device: device.to_string(),
        })
    };
    state(LiveState::Loading, "asr", "", "");
    let asr = pool::asr(&config.asr_model, config.asr_gpu)?;
    let provider = asr.lock().unwrap_or_else(|e| e.into_inner()).provider();
    let mut segmenter = Segmenter::new(&config.vad_model, config.segmenter)?;

    let worker = match (&config.translation, &jobs) {
        (Some(setup), Some(jobs)) => {
            state(LiveState::Loading, "translator", provider, "");
            let translator = make_translator(setup)?;
            let jobs = jobs.clone();
            let emit = emit.clone();
            Some(
                std::thread::Builder::new()
                    .name("fl-translate".into())
                    .spawn(move || translation_worker(translator, jobs, emit))?,
            )
        }
        _ => None,
    };
    let target = config.translation.as_ref().map(|t| t.config.target.clone());

    let (capture, rx) = match &config.file_source {
        Some(path) => capture::play_file(path)?,
        None => capture::start(config.source, config.device.as_deref())?,
    };
    state(LiveState::Running, "", provider, &capture.device_name);

    let mut next_id = 1u64;
    let mut last_audio = Instant::now();
    let mut last_partial = Instant::now();
    let mut partial_cost = Duration::ZERO;
    let mut partial_for: Option<usize> = None;
    let mut previous_partial = String::new();
    let mut level_sum = 0f32;
    let mut level_count = 0usize;
    let mut level_at = Instant::now();
    let interval = Duration::from_millis(config.partial_interval_ms.max(150));
    let mut agc = config.auto_gain.then(super::agc::AutoGain::default);

    let recognize = |samples: &[f32], options: &AsrOptions| {
        let started = Instant::now();
        let result = asr
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .recognize(samples, options);
        (result, started.elapsed())
    };

    let finish_utterance = |utterance: Utterance, id: u64| {
        let (options, replacements, skip_same, _) = snapshot(&tunables);
        let (result, cost) = recognize(&utterance.samples, &options);
        let recognized = match result {
            Ok(recognized) => recognized,
            Err(error) => {
                emit(LiveEvent::Error(format!("recognition: {error:#}")));
                return;
            }
        };
        let text = apply_replacements(&recognized.text, &replacements);
        if text.trim().is_empty() {
            // Clears the partial shown for it.
            emit(LiveEvent::Final {
                id,
                text: String::new(),
                language: None,
                emotion: None,
                start_ms: samples_to_ms(utterance.start),
                end_ms: samples_to_ms(utterance.end),
                asr_ms: cost.as_millis() as u64,
            });
            return;
        }
        let language = recognized
            .language
            .as_deref()
            .and_then(lang::from_asr_tag)
            .map(str::to_string);
        emit(LiveEvent::Final {
            id,
            text: text.clone(),
            language: language.clone(),
            emotion: recognized.emotion.clone(),
            start_ms: samples_to_ms(utterance.start),
            end_ms: samples_to_ms(utterance.end),
            asr_ms: cost.as_millis() as u64,
        });
        if let (Some(jobs), Some(target)) = (&jobs, &target) {
            let same = skip_same
                && language
                    .as_deref()
                    .is_some_and(|language| lang::same_language(language, target));
            if same {
                emit(LiveEvent::Translation {
                    id,
                    text,
                    partial: false,
                    done: true,
                    same_language: true,
                    first_token_ms: 0,
                    total_ms: 0,
                    prompt_tokens: 0,
                    cached_tokens: 0,
                });
            } else {
                jobs.push_final(id, text);
            }
        }
    };

    let result = loop {
        if stop.load(Ordering::Relaxed) {
            break Ok(());
        }
        let chunk = match rx.recv_timeout(Duration::from_millis(50)) {
            Ok(chunk) => {
                last_audio = Instant::now();
                chunk
            }
            Err(RecvTimeoutError::Timeout) => {
                if last_audio.elapsed() < GAP_FILL {
                    continue;
                }
                last_audio = Instant::now();
                vec![0.0; SAMPLE_RATE * GAP_FILL.as_millis() as usize / 1000]
            }
            Err(RecvTimeoutError::Disconnected) => break Err(anyhow!("the audio device stopped")),
        };
        level_sum += chunk.iter().map(|s| s * s).sum::<f32>();
        level_count += chunk.len();
        if level_at.elapsed() >= Duration::from_millis(100) && level_count > 0 {
            emit(LiveEvent::Level((level_sum / level_count as f32).sqrt()));
            level_sum = 0.0;
            level_count = 0;
            level_at = Instant::now();
        }
        let mut chunk = chunk;
        if let Some(agc) = agc.as_mut() {
            agc.process(&mut chunk);
        }
        let ended = match segmenter.push(&chunk) {
            Ok(ended) => ended,
            Err(error) => break Err(error),
        };
        for utterance in ended {
            // An utterance that had partials keeps their id.
            let id = match partial_for.take() {
                Some(start) if start == utterance.start => next_id - 1,
                _ => {
                    next_id += 1;
                    next_id - 1
                }
            };
            finish_utterance(utterance, id);
        }
        // A forced cut continues the speech as a new utterance.
        if let Some((start, samples)) = segmenter.ongoing() {
            let due = last_partial.elapsed() >= interval.max(partial_cost * 3 / 2);
            if samples.len() >= MIN_PARTIAL_SAMPLES && due {
                if partial_for != Some(start) {
                    partial_for = Some(start);
                    next_id += 1;
                    previous_partial.clear();
                }
                let id = next_id - 1;
                let samples = samples.to_vec();
                let (options, replacements, _, partials) = snapshot(&tunables);
                let (result, cost) = recognize(&samples, &options);
                partial_cost = cost;
                last_partial = Instant::now();
                match result {
                    Ok(recognized) => {
                        let text = apply_replacements(&recognized.text, &replacements);
                        if !text.trim().is_empty() {
                            let stable_chars = previous_partial
                                .chars()
                                .zip(text.chars())
                                .take_while(|(a, b)| a == b)
                                .count();
                            previous_partial = text.clone();
                            emit(LiveEvent::Partial {
                                id,
                                text: text.clone(),
                                start_ms: samples_to_ms(start),
                                end_ms: samples_to_ms(start + samples.len()),
                                stable_chars,
                                asr_ms: cost.as_millis() as u64,
                            });
                            if partials {
                                if let Some(jobs) = &jobs {
                                    jobs.push_partial(id, text);
                                }
                            }
                        }
                    }
                    Err(error) => emit(LiveEvent::Error(format!("recognition: {error:#}"))),
                }
            }
        }
    };
    drop(capture);
    if result.is_ok() {
        if let Some(utterance) = segmenter.finish() {
            let id = match partial_for.take() {
                Some(start) if start == utterance.start => next_id - 1,
                _ => next_id,
            };
            finish_utterance(utterance, id);
        }
    }
    if let Some(jobs) = &jobs {
        jobs.close();
    }
    if let Some(worker) = worker {
        let _ = worker.join();
    }
    drop(asr);
    pool::release_unused();
    result
}

fn snapshot(tunables: &Mutex<Tunables>) -> (AsrOptions, Vec<Replacement>, bool, bool) {
    let tunables = tunables.lock().unwrap_or_else(|e| e.into_inner());
    (
        tunables.asr_options.clone(),
        tunables.replacements.clone(),
        tunables.skip_same_language,
        tunables.translate_partials,
    )
}

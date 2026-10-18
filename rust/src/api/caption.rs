//! Live captions and file transcription.

use super::app::AudioSourceKind;
use crate::engine::asr::AsrOptions;
use crate::engine::filejob::{self, FileEvent, FileJobConfig, Stage};
use crate::engine::live::{self, BackendSetup, LiveConfig, LiveEvent, LiveState, TranslationSetup};
use crate::engine::segmenter::SegmenterConfig;
use crate::engine::subtitle::{CueRules, Format, Lines};
use crate::engine::text::{Replacement, Term};
use crate::engine::translate::{ApiConfig, PromptStyle, TranslatorConfig};
use crate::frb_generated::StreamSink;
use std::path::PathBuf;
use std::sync::Arc;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TranslatorBackend {
    Local,
    Api,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ApiPromptStyle {
    /// A general chat model (system prompt, history as turns).
    Chat,
    /// Hy-MT2 served by an API.
    TranslationModel,
}

#[derive(Debug, Clone)]
pub struct GlossaryTerm {
    pub source: String,
    pub target: String,
}

#[derive(Debug, Clone)]
pub struct ReplacementRule {
    pub from: String,
    pub to: String,
}

#[derive(Debug, Clone)]
pub struct TranslationSettings {
    pub backend: TranslatorBackend,
    pub local_model: String,
    pub local_gpu: bool,
    /// KV cache capacity of a local model, in tokens.
    pub context_tokens: u32,
    pub api_base_url: String,
    pub api_key: String,
    pub api_model: String,
    pub api_style: ApiPromptStyle,
    pub target_language: String,
    pub background: String,
    pub glossary: Vec<GlossaryTerm>,
    pub context_lines: u32,
    pub temperature: f32,
    pub translate_partials: bool,
    pub skip_same_language: bool,
}

impl TranslationSettings {
    fn backend_setup(&self) -> BackendSetup {
        match self.backend {
            TranslatorBackend::Local => BackendSetup::Local {
                model: self.local_model.clone(),
                gpu: self.local_gpu,
                context: self.context_tokens.clamp(512, 32_768) as usize,
            },
            TranslatorBackend::Api => BackendSetup::Api(ApiConfig {
                base_url: self.api_base_url.clone(),
                api_key: self.api_key.clone(),
                model: self.api_model.clone(),
                temperature: self.temperature,
                style: match self.api_style {
                    ApiPromptStyle::Chat => PromptStyle::Chat,
                    ApiPromptStyle::TranslationModel => PromptStyle::HyMt,
                },
            }),
        }
    }

    fn translator_config(&self) -> TranslatorConfig {
        TranslatorConfig {
            target: self.target_language.clone(),
            background: self.background.clone(),
            glossary: self
                .glossary
                .iter()
                .map(|term| Term {
                    source: term.source.clone(),
                    target: term.target.clone(),
                })
                .collect(),
            context_lines: self.context_lines.min(64) as usize,
            temperature: self.temperature.clamp(0.0, 2.0),
        }
    }
}

fn replacements(rules: &[ReplacementRule]) -> Vec<Replacement> {
    rules
        .iter()
        .map(|rule| Replacement {
            from: rule.from.clone(),
            to: rule.to.clone(),
        })
        .collect()
}

fn asr_options(hotwords: &[String], language: &Option<String>) -> AsrOptions {
    AsrOptions {
        hotwords: hotwords.to_vec(),
        language: language.clone().filter(|language| !language.is_empty()),
    }
}

#[derive(Debug, Clone)]
pub struct LiveSettings {
    pub asr_model: String,
    pub asr_gpu: bool,
    pub source: AudioSourceKind,
    pub device_id: Option<String>,
    pub vad_model_path: String,
    /// Off: every sound counts as speech; lines end after a finished
    /// sentence of their text, or at the longest allowed.
    pub vad_enabled: bool,
    pub vad_threshold: f32,
    pub min_silence_ms: u32,
    pub max_segment_ms: u32,
    pub partial_interval_ms: u32,
    pub auto_gain: bool,
    pub hotwords: Vec<String>,
    pub asr_language: Option<String>,
    pub replacements: Vec<ReplacementRule>,
    pub translation: Option<TranslationSettings>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CaptionEventKind {
    State,
    Level,
    Partial,
    Final,
    Translation,
    Error,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LiveStatus {
    Loading,
    Running,
    Stopped,
    Failed,
}

/// One flat event; `kind` says which fields matter.
#[derive(Debug, Clone)]
pub struct CaptionEvent {
    pub kind: CaptionEventKind,
    pub id: u64,
    pub text: String,
    pub language: Option<String>,
    pub emotion: Option<String>,
    pub start_ms: u64,
    pub end_ms: u64,
    pub asr_ms: u64,
    /// Partials: leading characters unchanged since the previous partial.
    pub stable_chars: u32,
    pub partial: bool,
    pub done: bool,
    pub same_language: bool,
    pub first_token_ms: u64,
    pub total_ms: u64,
    pub prompt_tokens: u32,
    pub cached_tokens: u32,
    pub level: f32,
    pub status: LiveStatus,
    pub message: String,
    pub asr_provider: String,
    pub device: String,
}

impl CaptionEvent {
    fn empty(kind: CaptionEventKind) -> Self {
        Self {
            kind,
            id: 0,
            text: String::new(),
            language: None,
            emotion: None,
            start_ms: 0,
            end_ms: 0,
            asr_ms: 0,
            stable_chars: 0,
            partial: false,
            done: false,
            same_language: false,
            first_token_ms: 0,
            total_ms: 0,
            prompt_tokens: 0,
            cached_tokens: 0,
            level: 0.0,
            status: LiveStatus::Running,
            message: String::new(),
            asr_provider: String::new(),
            device: String::new(),
        }
    }
}

impl From<LiveEvent> for CaptionEvent {
    fn from(event: LiveEvent) -> Self {
        match event {
            LiveEvent::State {
                state,
                message,
                asr_provider,
                device,
            } => Self {
                status: match state {
                    LiveState::Loading => LiveStatus::Loading,
                    LiveState::Running => LiveStatus::Running,
                    LiveState::Stopped => LiveStatus::Stopped,
                    LiveState::Failed => LiveStatus::Failed,
                },
                message,
                asr_provider,
                device,
                ..Self::empty(CaptionEventKind::State)
            },
            LiveEvent::Level(level) => Self {
                level,
                ..Self::empty(CaptionEventKind::Level)
            },
            LiveEvent::Partial {
                id,
                text,
                start_ms,
                end_ms,
                stable_chars,
                asr_ms,
            } => Self {
                id,
                text,
                start_ms,
                end_ms,
                stable_chars: stable_chars as u32,
                asr_ms,
                partial: true,
                ..Self::empty(CaptionEventKind::Partial)
            },
            LiveEvent::Final {
                id,
                text,
                language,
                emotion,
                start_ms,
                end_ms,
                asr_ms,
            } => Self {
                id,
                text,
                language,
                emotion,
                start_ms,
                end_ms,
                asr_ms,
                done: true,
                ..Self::empty(CaptionEventKind::Final)
            },
            LiveEvent::Translation {
                id,
                text,
                partial,
                done,
                same_language,
                first_token_ms,
                total_ms,
                prompt_tokens,
                cached_tokens,
            } => Self {
                id,
                text,
                partial,
                done,
                same_language,
                first_token_ms,
                total_ms,
                prompt_tokens: prompt_tokens as u32,
                cached_tokens: cached_tokens as u32,
                ..Self::empty(CaptionEventKind::Translation)
            },
            LiveEvent::Error(message) => Self {
                message,
                ..Self::empty(CaptionEventKind::Error)
            },
        }
    }
}

/// Starts live captions (stopping any running session); events until a
/// `State` event with `Stopped` or `Failed`.
pub fn start_live(settings: LiveSettings, sink: StreamSink<CaptionEvent>) {
    let defaults = SegmenterConfig::live();
    let config = LiveConfig {
        asr_model: settings.asr_model.clone(),
        asr_gpu: settings.asr_gpu,
        source: settings.source.into(),
        device: device_id_or_none(settings.device_id.clone()),
        vad_model: PathBuf::from(&settings.vad_model_path),
        segmenter: SegmenterConfig {
            vad: settings.vad_enabled,
            threshold: settings.vad_threshold.clamp(0.05, 0.95),
            min_silence_ms: (settings.min_silence_ms as usize).clamp(100, 3000),
            max_segment_ms: (settings.max_segment_ms as usize).clamp(3000, 28_000),
            ..defaults
        },
        partial_interval_ms: settings.partial_interval_ms as u64,
        auto_gain: settings.auto_gain,
        asr_options: asr_options(&settings.hotwords, &settings.asr_language),
        replacements: replacements(&settings.replacements),
        translation: settings
            .translation
            .as_ref()
            .map(|translation| TranslationSetup {
                backend: translation.backend_setup(),
                config: translation.translator_config(),
                translate_partials: translation.translate_partials,
                skip_same_language: translation.skip_same_language,
            }),
        file_source: std::env::var_os("FL_CAPTION_LIVE_FILE").map(PathBuf::from),
    };
    live::start(
        config,
        Arc::new(move |event| {
            let _ = sink.add(event.into());
        }),
    );
}

fn device_id_or_none(id: Option<String>) -> Option<String> {
    id.filter(|id| !id.is_empty())
}

pub fn stop_live() {
    live::stop();
}

/// Makes the running session's translator forget the earlier lines.
pub fn clear_live_context() {
    live::clear_context();
}

#[flutter_rust_bridge::frb(sync)]
pub fn live_running() -> bool {
    live::running()
}

/// Applies word lists and translation settings to the running session
/// (the translator model or backend itself needs a restart).
pub fn update_live(
    hotwords: Vec<String>,
    asr_language: Option<String>,
    rules: Vec<ReplacementRule>,
    translation: Option<TranslationSettings>,
) {
    live::update(
        asr_options(&hotwords, &asr_language),
        replacements(&rules),
        translation.map(|t| {
            (
                t.translator_config(),
                t.translate_partials,
                t.skip_same_language,
            )
        }),
    );
}

// ------------------------------------------------------------------ files

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SubtitleLines {
    Source,
    Translation,
    Both,
    BothTranslationFirst,
}

#[derive(Debug, Clone)]
pub struct FileJobSettings {
    pub input_path: String,
    pub output_dir: Option<String>,
    pub asr_model: String,
    pub asr_gpu: bool,
    pub vad_model_path: String,
    pub hotwords: Vec<String>,
    pub asr_language: Option<String>,
    pub replacements: Vec<ReplacementRule>,
    pub auto_gain: bool,
    /// `srt`, `vtt`, `lrc`, `txt`.
    pub formats: Vec<String>,
    pub lines: SubtitleLines,
    pub max_cue_ms: u32,
    pub max_cue_width: u32,
    pub strip_end_punctuation: bool,
    pub translation: Option<TranslationSettings>,
    pub ffmpeg_path: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FileJobEventKind {
    Progress,
    Cue,
    Done,
    Failed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FileJobStage {
    Decoding,
    Recognizing,
    Translating,
    Writing,
}

#[derive(Debug, Clone)]
pub struct FileJobEvent {
    pub kind: FileJobEventKind,
    pub stage: FileJobStage,
    pub done: u64,
    pub total: u64,
    pub index: u32,
    pub start_ms: u64,
    pub end_ms: u64,
    pub text: String,
    pub translation: Option<String>,
    pub files: Vec<String>,
    pub cues: u32,
    pub audio_ms: u64,
    pub elapsed_ms: u64,
    pub message: String,
}

impl FileJobEvent {
    fn empty(kind: FileJobEventKind) -> Self {
        Self {
            kind,
            stage: FileJobStage::Recognizing,
            done: 0,
            total: 0,
            index: 0,
            start_ms: 0,
            end_ms: 0,
            text: String::new(),
            translation: None,
            files: Vec::new(),
            cues: 0,
            audio_ms: 0,
            elapsed_ms: 0,
            message: String::new(),
        }
    }
}

impl From<FileEvent> for FileJobEvent {
    fn from(event: FileEvent) -> Self {
        match event {
            FileEvent::Progress { stage, done, total } => Self {
                stage: match stage {
                    Stage::Decoding => FileJobStage::Decoding,
                    Stage::Recognizing => FileJobStage::Recognizing,
                    Stage::Translating => FileJobStage::Translating,
                    Stage::Writing => FileJobStage::Writing,
                },
                done,
                total,
                ..Self::empty(FileJobEventKind::Progress)
            },
            FileEvent::Cue { index, cue } => Self {
                index: index as u32,
                start_ms: cue.start_ms,
                end_ms: cue.end_ms,
                text: cue.text,
                translation: cue.translation,
                ..Self::empty(FileJobEventKind::Cue)
            },
            FileEvent::Done {
                files,
                cues,
                audio_ms,
                elapsed_ms,
            } => Self {
                files: files.into_iter().map(|f| f.display().to_string()).collect(),
                cues: cues as u32,
                audio_ms,
                elapsed_ms,
                ..Self::empty(FileJobEventKind::Done)
            },
            FileEvent::Failed(message) => Self {
                message,
                ..Self::empty(FileJobEventKind::Failed)
            },
        }
    }
}

/// Transcribes a file into subtitle files; events until `Done` or `Failed`.
pub fn transcribe_file(job_id: String, settings: FileJobSettings, sink: StreamSink<FileJobEvent>) {
    let config = FileJobConfig {
        input: PathBuf::from(&settings.input_path),
        output_dir: settings
            .output_dir
            .clone()
            .filter(|dir| !dir.is_empty())
            .map(PathBuf::from),
        asr_model: settings.asr_model.clone(),
        asr_gpu: settings.asr_gpu,
        vad_model: PathBuf::from(&settings.vad_model_path),
        asr_options: asr_options(&settings.hotwords, &settings.asr_language),
        replacements: replacements(&settings.replacements),
        auto_gain: settings.auto_gain,
        formats: settings
            .formats
            .iter()
            .filter_map(|format| Format::parse(format))
            .collect(),
        lines: match settings.lines {
            SubtitleLines::Source => Lines::Source,
            SubtitleLines::Translation => Lines::Translation,
            SubtitleLines::Both => Lines::Both,
            SubtitleLines::BothTranslationFirst => Lines::BothTranslationFirst,
        },
        rules: CueRules {
            max_ms: (settings.max_cue_ms as u64).clamp(1500, 15_000),
            max_width: (settings.max_cue_width as usize).clamp(10, 120),
            strip_end_punctuation: settings.strip_end_punctuation,
        },
        translation: settings
            .translation
            .as_ref()
            .map(|t| (t.backend_setup(), t.translator_config())),
        ffmpeg: settings
            .ffmpeg_path
            .clone()
            .filter(|p| !p.is_empty())
            .map(PathBuf::from),
    };
    std::thread::spawn(move || {
        filejob::run(&job_id, config, &mut |event| {
            let _ = sink.add(event.into());
        });
    });
}

pub fn cancel_file_job(job_id: String) {
    filejob::cancel(&job_id);
}

pub struct TranslationTest {
    pub text: String,
    pub first_token_ms: u64,
    pub total_ms: u64,
}

/// Translates one line with `settings` (checks an API key or a local model).
pub fn test_translation(
    settings: TranslationSettings,
    text: String,
) -> anyhow::Result<TranslationTest> {
    use crate::engine::translate::{ApiClient, Backend, Translator};
    use crate::engine::{catalog, pool};
    let backend = match settings.backend_setup() {
        BackendSetup::Local {
            model,
            gpu,
            context,
        } => {
            let entry =
                catalog::find(&model).ok_or_else(|| anyhow::anyhow!("unknown model {model}"))?;
            Backend::Local {
                model: pool::chat(&model, gpu, context)?,
                style: PromptStyle::for_engine(entry.engine),
            }
        }
        BackendSetup::Api(api) => Backend::Api(ApiClient::new(api)?),
    };
    let mut translator = Translator::new(backend, settings.translator_config());
    let result = translator
        .translate(&text, false, None, &mut |_| true)?
        .ok_or_else(|| anyhow::anyhow!("cancelled"))?;
    Ok(TranslationTest {
        text: result.text,
        first_token_ms: result.first_token_ms,
        total_ms: result.total_ms,
    })
}

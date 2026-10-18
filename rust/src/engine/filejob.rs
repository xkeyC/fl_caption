//! Audio/video file → subtitles or lyrics.
//!
//! The file is decoded as a stream (infra's symphonia reader; formats it
//! cannot read go through ffmpeg into a temporary WAV first), cut by the
//! VAD, recognized segment by segment into cues, then optionally translated
//! line by line with the previous lines as context, and written out.

use super::asr::AsrOptions;
use super::live::BackendSetup;
use super::pool;
use super::segmenter::{Segmenter, SegmenterConfig, Utterance};
use super::subtitle::{self, Cue, CueRules, Format, Lines};
use super::text::{apply_replacements, Replacement};
use super::translate::{ApiClient, Backend, PromptStyle, Translator, TranslatorConfig};
use super::{catalog, samples_to_ms};
use anyhow::{anyhow, bail, Context, Result};
use local_adapter_sensevoice_asr::AudioStream;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Instant;

#[derive(Debug, Clone)]
pub struct FileJobConfig {
    pub input: PathBuf,
    /// Default: beside the input.
    pub output_dir: Option<PathBuf>,
    pub asr_model: String,
    pub asr_gpu: bool,
    pub vad_model: PathBuf,
    pub asr_options: AsrOptions,
    pub replacements: Vec<Replacement>,
    /// Boost quiet recordings before the VAD and the recognizer.
    pub auto_gain: bool,
    pub formats: Vec<Format>,
    pub lines: Lines,
    pub rules: CueRules,
    pub translation: Option<(BackendSetup, TranslatorConfig)>,
    pub ffmpeg: Option<PathBuf>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Stage {
    Decoding,
    Recognizing,
    Translating,
    Writing,
}

#[derive(Debug, Clone)]
pub enum FileEvent {
    Progress {
        stage: Stage,
        done: u64,
        total: u64,
    },
    Cue {
        index: usize,
        cue: Cue,
    },
    Done {
        files: Vec<PathBuf>,
        cues: usize,
        audio_ms: u64,
        elapsed_ms: u64,
    },
    Failed(String),
}

static JOBS: Mutex<Option<HashMap<String, Arc<AtomicBool>>>> = Mutex::new(None);

pub fn cancel(id: &str) {
    if let Some(flag) = JOBS
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .get_or_insert_with(HashMap::new)
        .get(id)
    {
        flag.store(true, Ordering::Relaxed);
    }
}

/// Runs a job to its end on the calling thread.
pub fn run(id: &str, config: FileJobConfig, emit: &mut dyn FnMut(FileEvent)) {
    let cancel = Arc::new(AtomicBool::new(false));
    JOBS.lock()
        .unwrap_or_else(|e| e.into_inner())
        .get_or_insert_with(HashMap::new)
        .insert(id.to_string(), cancel.clone());
    let started = Instant::now();
    let result = run_job(&config, &cancel, emit);
    JOBS.lock()
        .unwrap_or_else(|e| e.into_inner())
        .get_or_insert_with(HashMap::new)
        .remove(id);
    pool::release_unused();
    match result {
        Ok((files, cues, audio_ms)) => emit(FileEvent::Done {
            files,
            cues,
            audio_ms,
            elapsed_ms: started.elapsed().as_millis() as u64,
        }),
        Err(error) => emit(FileEvent::Failed(format!("{error:#}"))),
    }
}

struct TempFile(PathBuf);

impl Drop for TempFile {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.0);
    }
}

fn open_audio(
    config: &FileJobConfig,
    emit: &mut dyn FnMut(FileEvent),
) -> Result<(AudioStream, Option<TempFile>)> {
    match AudioStream::open(&config.input) {
        Ok(stream) => return Ok((stream, None)),
        Err(error) => tracing::info!(%error, "symphonia cannot read the file; trying ffmpeg"),
    }
    let ffmpeg = find_ffmpeg(config.ffmpeg.as_deref()).ok_or_else(|| {
        anyhow!(
            "this format needs ffmpeg: put ffmpeg on PATH or set its location ({})",
            config.input.display()
        )
    })?;
    emit(FileEvent::Progress {
        stage: Stage::Decoding,
        done: 0,
        total: 0,
    });
    let temp = TempFile(std::env::temp_dir().join(format!(
        "fl_caption-{}-{}.wav",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0)
    )));
    let mut command = Command::new(&ffmpeg);
    command
        .args(["-hide_banner", "-loglevel", "error", "-y", "-i"])
        .arg(&config.input)
        .args(["-vn", "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le"])
        .arg(&temp.0);
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        const CREATE_NO_WINDOW: u32 = 0x0800_0000;
        command.creation_flags(CREATE_NO_WINDOW);
    }
    let output = command
        .output()
        .with_context(|| format!("run {}", ffmpeg.display()))?;
    if !output.status.success() {
        bail!(
            "ffmpeg failed: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        );
    }
    let stream = AudioStream::open(&temp.0).map_err(|error| anyhow!("{error}"))?;
    Ok((stream, Some(temp)))
}

pub fn find_ffmpeg(configured: Option<&Path>) -> Option<PathBuf> {
    if let Some(path) = configured.filter(|path| path.is_file()) {
        return Some(path.to_path_buf());
    }
    let name = if cfg!(windows) {
        "ffmpeg.exe"
    } else {
        "ffmpeg"
    };
    let beside = std::env::current_exe()
        .ok()
        .and_then(|exe| exe.parent().map(Path::to_path_buf))
        .into_iter()
        .flat_map(|dir| {
            [
                dir.join(name),
                dir.join("runtime").join("ffmpeg").join(name),
            ]
        });
    let on_path = std::env::var_os("PATH")
        .map(|path| {
            std::env::split_paths(&path)
                .map(|dir| dir.join(name))
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    beside.chain(on_path).find(|path| path.is_file())
}

fn run_job(
    config: &FileJobConfig,
    cancel: &AtomicBool,
    emit: &mut dyn FnMut(FileEvent),
) -> Result<(Vec<PathBuf>, usize, u64)> {
    if config.formats.is_empty() {
        bail!("no output format chosen");
    }
    let asr = pool::asr(&config.asr_model, config.asr_gpu)?;
    let (mut stream, _temp) = open_audio(config, emit)?;
    let total_ms = stream.duration_ms().unwrap_or(0);
    let mut segmenter = Segmenter::new(&config.vad_model, SegmenterConfig::file())?;
    let mut cues: Vec<Cue> = Vec::new();
    let mut chunk = Vec::new();
    let mut position = 0usize;
    let mut agc = config.auto_gain.then(super::agc::AutoGain::default);
    let recognize = |utterance: Utterance,
                     cues: &mut Vec<Cue>,
                     emit: &mut dyn FnMut(FileEvent)|
     -> Result<()> {
        let recognized = asr
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .recognize(&utterance.samples, &config.asr_options)?;
        let mut recognized = recognized;
        recognized.text = apply_replacements(&recognized.text, &config.replacements);
        for mut cue in subtitle::segment_cues(
            samples_to_ms(utterance.start),
            samples_to_ms(utterance.end),
            &recognized,
            &config.rules,
        ) {
            // Token texts are the recognizer's own: the corrections go on
            // the cues as well.
            cue.text = apply_replacements(&cue.text, &config.replacements);
            cue.sentence = apply_replacements(&cue.sentence, &config.replacements);
            emit(FileEvent::Cue {
                index: cues.len(),
                cue: cue.clone(),
            });
            cues.push(cue);
        }
        Ok(())
    };
    loop {
        if cancel.load(Ordering::Relaxed) {
            bail!("cancelled");
        }
        chunk.clear();
        let more = stream
            .read(&mut chunk)
            .map_err(|error| anyhow!("{error}"))?;
        position += chunk.len();
        if let Some(agc) = agc.as_mut() {
            agc.process(&mut chunk);
        }
        for utterance in segmenter.push(&chunk)? {
            recognize(utterance, &mut cues, emit)?;
        }
        emit(FileEvent::Progress {
            stage: Stage::Recognizing,
            done: samples_to_ms(position),
            total: total_ms.max(samples_to_ms(position)),
        });
        if !more {
            break;
        }
    }
    if let Some(utterance) = segmenter.finish() {
        recognize(utterance, &mut cues, emit)?;
    }
    drop(asr);
    let audio_ms = samples_to_ms(position);

    if let Some((backend, translator_config)) = &config.translation {
        if config.lines != Lines::Source {
            translate_cues(
                backend,
                translator_config,
                &config.rules,
                &mut cues,
                cancel,
                emit,
            )?;
        }
    }

    emit(FileEvent::Progress {
        stage: Stage::Writing,
        done: 0,
        total: config.formats.len() as u64,
    });
    let dir = config
        .output_dir
        .clone()
        .or_else(|| config.input.parent().map(Path::to_path_buf))
        .unwrap_or_else(|| PathBuf::from("."));
    std::fs::create_dir_all(&dir)?;
    let stem = config
        .input
        .file_stem()
        .map(|stem| stem.to_string_lossy().into_owned())
        .unwrap_or_else(|| "subtitle".into());
    let mut files = Vec::new();
    for format in &config.formats {
        let path = dir.join(format!("{stem}.{}", format.extension()));
        let text = subtitle::render(&cues, *format, config.lines, &stem);
        std::fs::write(&path, text.as_bytes())
            .with_context(|| format!("write {}", path.display()))?;
        files.push(path);
    }
    Ok((files, cues.len(), audio_ms))
}

fn translate_cues(
    backend: &BackendSetup,
    config: &TranslatorConfig,
    rules: &CueRules,
    cues: &mut [Cue],
    cancel: &AtomicBool,
    emit: &mut dyn FnMut(FileEvent),
) -> Result<()> {
    let backend = match backend {
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
        BackendSetup::Api(api) => Backend::Api(ApiClient::new(api.clone())?),
    };
    let mut translator = Translator::new(backend, config.clone());
    let total = cues.len() as u64;
    // One request per sentence; its translation is split over its cues.
    let mut start = 0;
    while start < cues.len() {
        if cancel.load(Ordering::Relaxed) {
            bail!("cancelled");
        }
        let key = cues[start].sentence_key;
        let end = start
            + cues[start..]
                .iter()
                .take_while(|cue| cue.sentence_key == key)
                .count();
        let sentence = if cues[start].sentence.is_empty() {
            cues[start..end]
                .iter()
                .map(|cue| cue.text.as_str())
                .collect::<Vec<_>>()
                .join(" ")
        } else {
            cues[start].sentence.clone()
        };
        let translation = translator
            .translate(&sentence, true, None, &mut |_| {
                !cancel.load(Ordering::Relaxed)
            })?
            .ok_or_else(|| anyhow!("cancelled"))?;
        let weights: Vec<usize> = cues[start..end]
            .iter()
            .map(|cue| crate::engine::lang::width(&cue.text).max(1))
            .collect();
        let pieces = subtitle::split_translation(&translation.text, &weights, rules);
        for (offset, piece) in pieces.into_iter().enumerate() {
            let index = start + offset;
            cues[index].translation = Some(piece);
            emit(FileEvent::Cue {
                index,
                cue: cues[index].clone(),
            });
        }
        emit(FileEvent::Progress {
            stage: Stage::Translating,
            done: end as u64,
            total,
        });
        start = end;
    }
    Ok(())
}

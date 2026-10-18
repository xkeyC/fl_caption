//! Real-model checks and timings of the engine, outside Flutter.
//!
//! ```text
//! bench file      <asr model> <cpu|gpu> <audio> <out dir> [translator] [target]
//! bench live      <asr model> <audio> [translator] [target]
//! bench translate <translator> <pairs.tsv> <target> <out.tsv> [context lines]
//! ```
//! Models are read from `FL_CAPTION_MODELS` (default: infra's
//! workdir/models); `FL_CAPTION_IMPORT=<id>=<dir>,...` maps ids to other
//! directories. ONNX Runtime comes from `ORT_DYLIB_PATH`.

use rust_lib_fl_caption::engine::asr::AsrOptions;
use rust_lib_fl_caption::engine::filejob::{self, FileEvent, FileJobConfig};
use rust_lib_fl_caption::engine::live::{
    self, BackendSetup, LiveConfig, LiveEvent, TranslationSetup,
};
use rust_lib_fl_caption::engine::segmenter::SegmenterConfig;
use rust_lib_fl_caption::engine::subtitle::{CueRules, Format, Lines};
use rust_lib_fl_caption::engine::translate::{Backend, PromptStyle, Translator, TranslatorConfig};
use rust_lib_fl_caption::engine::{capture, catalog, pool, runtime, store};
use std::collections::HashMap;
use std::io::Write;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

fn vram() -> u64 {
    runtime::gpus().first().map(|gpu| gpu.used_mb).unwrap_or(0)
}

fn setup() {
    let _ = tracing_subscriber::fmt()
        .with_env_filter(
            std::env::var("FL_CAPTION_LOG")
                .unwrap_or_else(|_| "warn,rust_lib_fl_caption=info".into()),
        )
        .try_init();
    let root = std::env::var("FL_CAPTION_MODELS")
        .unwrap_or_else(|_| "../../local-multimodal-infra/workdir/models".into());
    let mut overrides = HashMap::new();
    for pair in std::env::var("FL_CAPTION_IMPORT")
        .unwrap_or_default()
        .split(',')
    {
        if let Some((id, dir)) = pair.split_once('=') {
            overrides.insert(id.to_string(), PathBuf::from(dir));
        }
    }
    store::configure(PathBuf::from(root), overrides, None);
    let state = runtime::init(&[std::env::current_dir().unwrap()]);
    if let Some(error) = state.error {
        panic!("{error}");
    }
}

fn vad() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../assets/models/silero_vad.onnx")
}

fn translator_setup(
    model: &str,
    target: &str,
    glossary: Vec<rust_lib_fl_caption::engine::text::Term>,
) -> (BackendSetup, TranslatorConfig) {
    (
        BackendSetup::Local {
            model: model.to_string(),
            gpu: true,
            context: 4096,
        },
        TranslatorConfig {
            target: target.to_string(),
            background: String::new(),
            glossary,
            context_lines: 4,
            temperature: 0.0,
        },
    )
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    setup();
    let base = vram();
    match args.first().map(String::as_str) {
        Some("file") => {
            let started = Instant::now();
            let translation = args.get(5).map(|model| {
                translator_setup(
                    model,
                    args.get(6).map(String::as_str).unwrap_or("zh"),
                    Vec::new(),
                )
            });
            let config = FileJobConfig {
                input: PathBuf::from(&args[3]),
                output_dir: Some(PathBuf::from(&args[4])),
                asr_model: args[1].clone(),
                asr_gpu: args[2] == "gpu",
                vad_model: vad(),
                asr_options: asr_options(),
                replacements: Vec::new(),
                auto_gain: std::env::var_os("FL_CAPTION_AGC").is_some(),
                formats: vec![Format::Srt, Format::Lrc, Format::Txt],
                lines: if translation.is_some() {
                    Lines::Both
                } else {
                    Lines::Source
                },
                rules: CueRules::default(),
                translation,
                ffmpeg: None,
            };
            let peak = Arc::new(Mutex::new(0u64));
            let mut last_stage = None;
            filejob::run("bench", config, &mut |event| {
                let mut peak = peak.lock().unwrap();
                *peak = (*peak).max(vram());
                match event {
                    FileEvent::Progress { stage, .. } if last_stage != Some(stage) => {
                        println!("[{:>6} ms] stage {stage:?}", started.elapsed().as_millis());
                        last_stage = Some(stage);
                    }
                    FileEvent::Done {
                        files,
                        cues,
                        audio_ms,
                        elapsed_ms,
                    } => {
                        println!(
                            "done: {cues} cues, audio {:.1} s in {:.2} s (RTF {:.4}), files {files:?}",
                            audio_ms as f64 / 1000.0,
                            elapsed_ms as f64 / 1000.0,
                            elapsed_ms as f64 / audio_ms.max(1) as f64
                        );
                    }
                    FileEvent::Failed(message) => println!("FAILED: {message}"),
                    _ => {}
                }
            });
            println!(
                "VRAM: base {base} MB, peak +{} MB",
                peak.lock().unwrap().saturating_sub(base)
            );
        }
        Some("live") => {
            let translation = args.get(3).map(|model| {
                let (backend, config) = translator_setup(
                    model,
                    args.get(4).map(String::as_str).unwrap_or("zh"),
                    Vec::new(),
                );
                TranslationSetup {
                    backend,
                    config,
                    translate_partials: true,
                    skip_same_language: true,
                }
            });
            let config = LiveConfig {
                asr_model: args[1].clone(),
                asr_gpu: true,
                source: capture::SourceKind::System,
                device: None,
                vad_model: vad(),
                segmenter: SegmenterConfig {
                    // FL_CAPTION_NO_VAD: every sound counts as speech.
                    vad: std::env::var_os("FL_CAPTION_NO_VAD").is_none(),
                    ..SegmenterConfig::live()
                },
                partial_interval_ms: 400,
                auto_gain: std::env::var_os("FL_CAPTION_AGC").is_some(),
                asr_options: asr_options(),
                replacements: Vec::new(),
                translation,
                file_source: Some(PathBuf::from(&args[2])),
                remote_source: None,
            };
            let started = Instant::now();
            // Audio time 0 is when the session starts running (models
            // loaded): lags are measured from there.
            let running_at = Arc::new(Mutex::new(None::<u128>));
            let running_in = running_at.clone();
            let done = Arc::new(Mutex::new(false));
            let stats = Arc::new(Mutex::new(LiveStats::default()));
            let (done_in, stats_in) = (done.clone(), stats.clone());
            live::start(
                config,
                Arc::new(move |event| {
                    let wall = started.elapsed().as_millis();
                    let offset = running_in.lock().unwrap().unwrap_or(0);
                    // Milliseconds of audio time (since the audio began).
                    let at = wall.saturating_sub(offset);
                    let mut stats = stats_in.lock().unwrap();
                    stats.peak = stats.peak.max(vram());
                    match event {
                        LiveEvent::State {
                            state,
                            message,
                            asr_provider,
                            device,
                        } => {
                            if state == live::LiveState::Running {
                                *running_in.lock().unwrap() = Some(wall);
                            }
                            println!(
                                "[{wall:>6}] state {state:?} {message} {asr_provider} {device}"
                            );
                            if matches!(state, live::LiveState::Stopped | live::LiveState::Failed) {
                                *done_in.lock().unwrap() = true;
                            }
                        }
                        LiveEvent::Partial {
                            id,
                            text,
                            end_ms,
                            asr_ms,
                            ..
                        } => {
                            stats.partials += 1;
                            stats.partial_asr_ms += asr_ms;
                            // Wall time vs the audio it covers: how far the
                            // caption trails the speech.
                            let lag = (at as u64).saturating_sub(end_ms);
                            stats.partial_lag_ms += lag;
                            println!(
                                "[{at:>6}] #{id} partial (asr {asr_ms} ms, lag {lag} ms) {text}..."
                            );
                        }
                        LiveEvent::Final {
                            id,
                            text,
                            language,
                            end_ms,
                            asr_ms,
                            ..
                        } => {
                            stats.finals += 1;
                            stats.final_asr_ms += asr_ms;
                            // Audio time vs wall time: how long after the speech
                            // ended the final caption appeared.
                            stats.final_lag_ms += (at as u64).saturating_sub(end_ms);
                            println!("[{at:>6}] #{id} FINAL ({language:?}, asr {asr_ms} ms, lag {} ms) {text}", (at as u64).saturating_sub(end_ms));
                        }
                        LiveEvent::Translation {
                            id,
                            text,
                            partial,
                            done: true,
                            same_language,
                            first_token_ms,
                            total_ms,
                            prompt_tokens,
                            cached_tokens,
                        } => {
                            if partial {
                                stats.partial_translations += 1;
                                stats.partial_translation_ms += total_ms;
                                println!("[{at:>6}] #{id} partial translation ({total_ms} ms, {cached_tokens}/{prompt_tokens} cached) {text}...");
                            } else {
                                stats.translations += 1;
                                stats.translation_ms += total_ms;
                                stats.prompt_tokens += prompt_tokens;
                                stats.cached_tokens += cached_tokens;
                                println!("[{at:>6}] #{id} TRANSLATION ({first_token_ms}/{total_ms} ms, {cached_tokens}/{prompt_tokens} cached, same {same_language}) {text}");
                            }
                        }
                        LiveEvent::Error(message) => println!("[{at:>6}] ERROR {message}"),
                        _ => {}
                    }
                }),
            );
            while !*done.lock().unwrap() {
                std::thread::sleep(Duration::from_millis(200));
            }
            live::stop();
            let stats = stats.lock().unwrap();
            println!("{stats:#?}");
            println!(
                "avg final ASR {} ms, avg partial ASR {} ms, avg partial lag {} ms, avg partial translation {} ms ({} done), avg final lag {} ms, avg translation {} ms, KV reuse {:.0}%; VRAM base {base} MB peak +{} MB",
                stats.final_asr_ms / stats.finals.max(1) as u64,
                stats.partial_asr_ms / stats.partials.max(1) as u64,
                stats.partial_lag_ms / stats.partials.max(1) as u64,
                stats.partial_translation_ms / stats.partial_translations.max(1) as u64,
                stats.partial_translations,
                stats.final_lag_ms / stats.finals.max(1) as u64,
                stats.translation_ms / stats.translations.max(1) as u64,
                100.0 * stats.cached_tokens as f64 / stats.prompt_tokens.max(1) as f64,
                stats.peak.saturating_sub(base)
            );
        }
        Some("translate") => {
            let model = &args[1];
            let entry = catalog::find(model).expect("unknown model");
            let load = Instant::now();
            let chat = pool::chat(model, true, 4096).expect("load");
            let loaded_ms = load.elapsed().as_millis();
            let after_load = vram();
            let context = args.get(5).and_then(|n| n.parse().ok()).unwrap_or(4);
            let mut translator = Translator::new(
                Backend::Local {
                    model: chat,
                    style: PromptStyle::for_engine(entry.engine),
                },
                TranslatorConfig {
                    target: args[3].clone(),
                    background: std::env::var("FL_CAPTION_BACKGROUND").unwrap_or_default(),
                    // FL_CAPTION_GLOSSARY="source=target;..."
                    glossary: std::env::var("FL_CAPTION_GLOSSARY")
                        .unwrap_or_default()
                        .split(';')
                        .filter_map(|pair| pair.split_once('='))
                        .map(|(source, target)| rust_lib_fl_caption::engine::text::Term {
                            source: source.trim().into(),
                            target: target.trim().into(),
                        })
                        .collect(),
                    context_lines: context,
                    temperature: 0.0,
                },
            );
            let mut out = std::fs::File::create(&args[4]).ok();
            let rows: Vec<Vec<String>> = std::fs::read_to_string(&args[2])
                .unwrap()
                .lines()
                .map(|line| line.split('\t').map(str::to_string).collect())
                .collect();
            let mut total_ms = 0;
            let mut first_ms = 0;
            let (mut prompt, mut cached) = (0, 0);
            let mut peak = after_load;
            let mut outputs = Vec::new();
            for row in &rows {
                let result = translator
                    .translate(&row[1], true, None, &mut |_| true)
                    .unwrap()
                    .unwrap();
                total_ms += result.total_ms;
                first_ms += result.first_token_ms;
                prompt += result.prompt_tokens;
                cached += result.cached_tokens;
                peak = peak.max(vram());
                outputs.push(format!(
                    "{}\t{}\t{}\t{}",
                    row[0], row[1], row[2], result.text
                ));
            }
            if let Some(file) = out.as_mut() {
                let _ = file.write_all(outputs.join("\n").as_bytes());
            }
            let n = rows.len().max(1) as u64;
            println!(
                "{model}: {} lines, load {loaded_ms} ms, avg first token {} ms, avg total {} ms, KV reuse {:.0}% ({cached}/{prompt}), VRAM base {base} MB, after load +{} MB, peak +{} MB",
                rows.len(),
                first_ms / n,
                total_ms / n,
                100.0 * cached as f64 / prompt.max(1) as f64,
                after_load.saturating_sub(base),
                peak.saturating_sub(base)
            );
        }
        Some("download") => {
            let started = Instant::now();
            let mut last = Instant::now();
            let result = store::download(&args[1], |p| {
                if last.elapsed() > Duration::from_secs(2) {
                    last = Instant::now();
                    println!(
                        "{}/{} {} {:.0} MB / {:.0} MB  {:.1} MB/s",
                        p.file_index + 1,
                        p.file_count,
                        p.file,
                        p.downloaded as f64 / 1048576.0,
                        p.total as f64 / 1048576.0,
                        p.speed as f64 / 1048576.0
                    );
                }
            });
            println!(
                "download {:?} in {:.1} s",
                result.err().map(|e| format!("{e:#}")),
                started.elapsed().as_secs_f64()
            );
            let entry = catalog::find(&args[1]).unwrap();
            println!(
                "installed: {}",
                store::install_state(&entry).unwrap().installed
            );
        }
        Some("models") => {
            for entry in catalog::catalog() {
                let state = store::install_state(&entry).unwrap();
                let check = store::validate_package(&entry, &state.dir);
                println!(
                    "{:36} installed={} imported={} dir={} check={:?}",
                    entry.id,
                    state.installed,
                    state.imported,
                    state.dir.display(),
                    check.err().map(|e| e.to_string())
                );
            }
        }
        _ => eprintln!("usage: see the module documentation"),
    }
}

#[derive(Debug, Default)]
struct LiveStats {
    partials: usize,
    partial_asr_ms: u64,
    partial_lag_ms: u64,
    partial_translation_ms: u64,
    finals: usize,
    final_asr_ms: u64,
    final_lag_ms: u64,
    translations: usize,
    partial_translations: usize,
    translation_ms: u64,
    prompt_tokens: usize,
    cached_tokens: usize,
    peak: u64,
}

/// `FL_CAPTION_ASR_LANGUAGE`: the spoken language (detected when unset).
fn asr_options() -> AsrOptions {
    AsrOptions {
        language: std::env::var("FL_CAPTION_ASR_LANGUAGE").ok(),
        ..AsrOptions::default()
    }
}

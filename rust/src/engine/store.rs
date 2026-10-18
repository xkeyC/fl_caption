//! Where models live, whether they are installed, and downloading them.
//!
//! A model is `<models root>/<id>/` unless the user imported a directory
//! elsewhere (an override). Downloads resume from `<file>.part`, check the
//! size and SHA-256, and finish with a `.fl_caption.json` marker listing the
//! files, which the install check reads.

use super::catalog::{self, CatalogEntry, Hosted, UrlFile};
use anyhow::{anyhow, bail, Context, Result};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::fs;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, RwLock};
use std::time::{Duration, Instant};

const MARKER: &str = ".fl_caption.json";
pub const DEFAULT_HF_ENDPOINT: &str = "https://huggingface.co";

#[derive(Debug, Clone, Default)]
struct StoreConfig {
    root: PathBuf,
    overrides: HashMap<String, PathBuf>,
    hf_endpoint: String,
}

static CONFIG: RwLock<Option<StoreConfig>> = RwLock::new(None);

pub fn configure(root: PathBuf, overrides: HashMap<String, PathBuf>, hf_endpoint: Option<String>) {
    let hf_endpoint = hf_endpoint
        .map(|endpoint| endpoint.trim().trim_end_matches('/').to_string())
        .filter(|endpoint| !endpoint.is_empty())
        .unwrap_or_else(|| DEFAULT_HF_ENDPOINT.to_string());
    *CONFIG.write().unwrap_or_else(|e| e.into_inner()) = Some(StoreConfig {
        root,
        overrides,
        hf_endpoint,
    });
}

fn config() -> Result<StoreConfig> {
    CONFIG
        .read()
        .unwrap_or_else(|e| e.into_inner())
        .clone()
        .ok_or_else(|| anyhow!("the model store is not configured"))
}

/// The directory model `id` is (or would be) installed in.
pub fn model_dir(id: &str) -> Result<PathBuf> {
    let config = config()?;
    Ok(config
        .overrides
        .get(id)
        .cloned()
        .unwrap_or_else(|| config.root.join(id)))
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct Marker {
    id: String,
    files: Vec<MarkerFile>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct MarkerFile {
    path: String,
    size: u64,
}

#[derive(Debug, Clone)]
pub struct InstallState {
    pub installed: bool,
    /// Imported from a directory outside the models root.
    pub imported: bool,
    pub dir: PathBuf,
    /// Bytes on disk of the model's files (complete or partial).
    pub bytes_on_disk: u64,
}

pub fn install_state(entry: &CatalogEntry) -> Result<InstallState> {
    let config = config()?;
    let imported = config.overrides.contains_key(entry.id);
    let dir = model_dir(entry.id)?;
    // A package placed in the models directory by hand (an export) counts
    // as well: downloads only rename complete, verified files into place.
    let installed = marker_complete(&dir, entry.id) || validate_package(entry, &dir).is_ok();
    Ok(InstallState {
        installed,
        imported,
        bytes_on_disk: dir_size(&dir),
        dir,
    })
}

fn marker_complete(dir: &Path, id: &str) -> bool {
    let Ok(text) = fs::read_to_string(dir.join(MARKER)) else {
        return false;
    };
    let Ok(marker) = serde_json::from_str::<Marker>(&text) else {
        return false;
    };
    marker.id == id
        && !marker.files.is_empty()
        && marker.files.iter().all(|file| {
            fs::metadata(dir.join(&file.path)).is_ok_and(|meta| meta.len() == file.size)
        })
}

fn dir_size(dir: &Path) -> u64 {
    let Ok(entries) = fs::read_dir(dir) else {
        return 0;
    };
    entries
        .flatten()
        .map(|entry| match entry.file_type() {
            Ok(kind) if kind.is_dir() => dir_size(&entry.path()),
            Ok(_) => entry.metadata().map(|meta| meta.len()).unwrap_or(0),
            Err(_) => 0,
        })
        .sum()
}

/// Checks that `dir` holds a package the model's adapter can load (file
/// layout only; nothing is loaded).
pub fn validate_package(entry: &CatalogEntry, dir: &Path) -> Result<()> {
    use local_adapter_fun_asr_nano::FunAsrNanoArtifacts;
    use local_adapter_sensevoice_asr::SenseVoiceArtifacts;
    match entry.engine {
        catalog::Engine::SenseVoice => {
            let model_file = entry
                .metadata()
                .get("asr_model_file")
                .and_then(|value| value.as_str().map(str::to_string))
                .unwrap_or_else(|| "model_quant.onnx".to_string());
            SenseVoiceArtifacts::validate_with_model(dir, &model_file)
                .map(|_| ())
                .map_err(|error| anyhow!("{error}"))
        }
        catalog::Engine::FunAsrNano => FunAsrNanoArtifacts::validate(dir)
            .map(|_| ())
            .map_err(|error| anyhow!("{error}")),
        catalog::Engine::HyMt | catalog::Engine::ChatLlm => {
            for name in ["genai_config.json", "tokenizer.json"] {
                if !dir.join(name).is_file() {
                    bail!("{} has no {name}", dir.display());
                }
            }
            if !dir.join("chat_template.jinja").is_file()
                && !dir.join("tokenizer_config.json").is_file()
            {
                bail!("{} has no chat_template.jinja", dir.display());
            }
            let config: serde_json::Value =
                serde_json::from_str(&fs::read_to_string(dir.join("genai_config.json"))?)?;
            let model = config["model"]["decoder"]["filename"]
                .as_str()
                .unwrap_or("model.onnx");
            if !dir.join(model).is_file() {
                bail!("{} has no {model}", dir.display());
            }
            Ok(())
        }
    }
}

/// Deletes a downloaded model (never an imported directory: only the
/// override is dropped, by the caller).
pub fn delete(entry: &CatalogEntry) -> Result<()> {
    let config = config()?;
    if config.overrides.contains_key(entry.id) {
        bail!(
            "{} is an imported directory; remove the import instead",
            entry.id
        );
    }
    let dir = config.root.join(entry.id);
    if dir.is_dir() {
        fs::remove_dir_all(&dir).with_context(|| format!("remove {}", dir.display()))?;
    }
    Ok(())
}

// ------------------------------------------------------------------ downloads

#[derive(Debug, Clone, Default)]
pub struct Progress {
    pub file: String,
    pub file_index: usize,
    pub file_count: usize,
    pub downloaded: u64,
    pub total: u64,
    /// Bytes per second over the last second.
    pub speed: u64,
}

struct Job {
    cancel: Arc<AtomicBool>,
}

static JOBS: Mutex<Option<HashMap<String, Job>>> = Mutex::new(None);

pub fn cancel_download(id: &str) {
    if let Some(job) = JOBS
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .get_or_insert_with(HashMap::new)
        .get(id)
    {
        job.cancel.store(true, Ordering::Relaxed);
    }
}

pub fn downloading(id: &str) -> bool {
    JOBS.lock()
        .unwrap_or_else(|e| e.into_inner())
        .get_or_insert_with(HashMap::new)
        .contains_key(id)
}

#[derive(Debug, Clone)]
struct PlannedFile {
    path: String,
    url: String,
    size: Option<u64>,
    sha256: Option<String>,
}

/// Downloads model `id` into its directory, reporting progress; blocks
/// until it is done, failed or cancelled.
pub fn download(id: &str, mut progress: impl FnMut(&Progress)) -> Result<()> {
    let entry = catalog::find(id).ok_or_else(|| anyhow!("unknown model {id}"))?;
    let config = config()?;
    if config.overrides.contains_key(id) {
        bail!("{id} is imported from a directory");
    }
    if !entry.downloadable() {
        bail!("{id} is not published for download yet; import an exported package");
    }
    let cancel = Arc::new(AtomicBool::new(false));
    {
        let mut jobs = JOBS.lock().unwrap_or_else(|e| e.into_inner());
        let jobs = jobs.get_or_insert_with(HashMap::new);
        if jobs.contains_key(id) {
            bail!("{id} is already downloading");
        }
        jobs.insert(
            id.to_string(),
            Job {
                cancel: cancel.clone(),
            },
        );
    }
    let result = run_download(&entry, &config, &cancel, &mut progress);
    JOBS.lock()
        .unwrap_or_else(|e| e.into_inner())
        .get_or_insert_with(HashMap::new)
        .remove(id);
    result
}

fn client() -> Result<reqwest::blocking::Client> {
    Ok(reqwest::blocking::Client::builder()
        .user_agent(concat!("fl_caption/", env!("CARGO_PKG_VERSION")))
        .connect_timeout(Duration::from_secs(20))
        // A stalled transfer errors out instead of hanging (resumed later).
        .timeout(None)
        .build()?)
}

fn run_download(
    entry: &CatalogEntry,
    config: &StoreConfig,
    cancel: &AtomicBool,
    progress: &mut dyn FnMut(&Progress),
) -> Result<()> {
    let client = client()?;
    let dir = config.root.join(entry.id);
    fs::create_dir_all(&dir).with_context(|| format!("create {}", dir.display()))?;
    let _ = fs::remove_file(dir.join(MARKER));
    let mut files: Vec<PlannedFile> = entry
        .files
        .iter()
        .map(|file: &UrlFile| PlannedFile {
            path: file.path.to_string(),
            url: rewrite_hf(file.url, &config.hf_endpoint),
            size: Some(file.size),
            sha256: Some(file.sha256.to_string()),
        })
        .collect();
    if let Some(hosted) = entry.hosted {
        files.extend(list_hosted(&client, &config.hf_endpoint, hosted)?);
    }
    let total: u64 = files.iter().filter_map(|file| file.size).sum();
    let mut done_bytes = 0u64;
    let mut state = Progress {
        file_count: files.len(),
        total,
        ..Progress::default()
    };
    let mut marker = Marker {
        id: entry.id.to_string(),
        files: Vec::new(),
    };
    let mut meter = SpeedMeter::new();
    for (index, file) in files.iter().enumerate() {
        state.file = file.path.clone();
        state.file_index = index;
        let target = dir.join(&file.path);
        if let Some(parent) = target.parent() {
            fs::create_dir_all(parent)?;
        }
        let size = fetch(&client, file, &target, cancel, &mut |bytes| {
            state.downloaded = done_bytes + bytes;
            state.speed = meter.update(state.downloaded);
            progress(&state);
        })?;
        done_bytes += size;
        marker.files.push(MarkerFile {
            path: file.path.clone(),
            size,
        });
    }
    fs::write(dir.join(MARKER), serde_json::to_vec_pretty(&marker)?)?;
    state.downloaded = total.max(done_bytes);
    progress(&state);
    Ok(())
}

fn rewrite_hf(url: &str, endpoint: &str) -> String {
    match url.strip_prefix(DEFAULT_HF_ENDPOINT) {
        Some(rest) if endpoint != DEFAULT_HF_ENDPOINT => format!("{endpoint}{rest}"),
        _ => url.to_string(),
    }
}

#[derive(Deserialize)]
struct TreeItem {
    #[serde(rename = "type")]
    kind: String,
    path: String,
    #[serde(default)]
    size: u64,
    #[serde(default)]
    lfs: Option<TreeLfs>,
}

#[derive(Deserialize)]
struct TreeLfs {
    oid: String,
    size: u64,
}

/// The published package's files through the Hub API
/// (`/api/models/.../tree`), `config.json` (which the Hub counts downloads
/// by) and the model card included.
fn list_hosted(
    client: &reqwest::blocking::Client,
    endpoint: &str,
    hosted: Hosted,
) -> Result<Vec<PlannedFile>> {
    let Hosted { repo, revision } = hosted;
    let revision = revision.ok_or_else(|| anyhow!("{repo} is not published yet"))?;
    let url = format!("{endpoint}/api/models/{repo}/tree/{revision}?recursive=true");
    let items: Vec<TreeItem> = client
        .get(&url)
        .send()
        .and_then(reqwest::blocking::Response::error_for_status)
        .with_context(|| format!("list {url}"))?
        .json()?;
    let files: Vec<PlannedFile> = items
        .into_iter()
        .filter(|item| item.kind == "file" && item.path != ".gitattributes")
        .map(|item| {
            let (size, sha256) = match item.lfs {
                Some(lfs) => (lfs.size, Some(lfs.oid)),
                None => (item.size, None),
            };
            PlannedFile {
                url: format!("{endpoint}/{repo}/resolve/{revision}/{}", item.path),
                path: item.path,
                size: Some(size),
                sha256,
            }
        })
        .collect();
    if files.is_empty() {
        bail!("{repo}@{revision} has no files");
    }
    Ok(files)
}

/// Downloads one file to `target` (resuming `<target>.part`); returns its
/// size. A complete file with the right size and digest is kept.
fn fetch(
    client: &reqwest::blocking::Client,
    file: &PlannedFile,
    target: &Path,
    cancel: &AtomicBool,
    progress: &mut dyn FnMut(u64),
) -> Result<u64> {
    if let (Ok(meta), Some(size)) = (fs::metadata(target), file.size) {
        if meta.len() == size && digest_matches(target, file.sha256.as_deref())? {
            progress(size);
            return Ok(size);
        }
    }
    let part = PathBuf::from(format!("{}.part", target.display()));
    let mut attempt = 0;
    loop {
        attempt += 1;
        match fetch_once(client, file, &part, cancel, progress) {
            Ok(()) => break,
            Err(error) if cancel.load(Ordering::Relaxed) => return Err(error),
            Err(error) if attempt < 5 => {
                tracing::warn!(url = file.url, attempt, %error, "download interrupted; resuming");
                std::thread::sleep(Duration::from_secs(2 * attempt));
            }
            Err(error) => return Err(error),
        }
    }
    let size = fs::metadata(&part)?.len();
    if let Some(expected) = file.size {
        if size != expected {
            let _ = fs::remove_file(&part);
            bail!("{}: got {size} bytes, expected {expected}", file.path);
        }
    }
    if !digest_matches(&part, file.sha256.as_deref())? {
        let _ = fs::remove_file(&part);
        bail!("{}: SHA-256 mismatch", file.path);
    }
    let _ = fs::remove_file(target);
    fs::rename(&part, target)?;
    Ok(size)
}

fn fetch_once(
    client: &reqwest::blocking::Client,
    file: &PlannedFile,
    part: &Path,
    cancel: &AtomicBool,
    progress: &mut dyn FnMut(u64),
) -> Result<()> {
    let have = fs::metadata(part).map(|meta| meta.len()).unwrap_or(0);
    if file.size.is_some_and(|size| have == size) {
        return Ok(());
    }
    let mut request = client.get(&file.url);
    if have > 0 {
        request = request.header(reqwest::header::RANGE, format!("bytes={have}-"));
    }
    let mut response = request
        .send()
        .and_then(reqwest::blocking::Response::error_for_status)
        .with_context(|| format!("download {}", file.url))?;
    let resumed = response.status() == reqwest::StatusCode::PARTIAL_CONTENT;
    let mut out = fs::OpenOptions::new()
        .create(true)
        .append(resumed)
        .write(true)
        .truncate(!resumed)
        .open(part)?;
    let mut written = if resumed { have } else { 0 };
    let mut buffer = vec![0u8; 1 << 20];
    loop {
        if cancel.load(Ordering::Relaxed) {
            bail!("cancelled");
        }
        let read = response.read(&mut buffer)?;
        if read == 0 {
            break;
        }
        out.write_all(&buffer[..read])?;
        written += read as u64;
        progress(written);
    }
    out.flush()?;
    if let Some(size) = file.size {
        if written < size {
            bail!("connection closed at {written} of {size} bytes");
        }
    }
    Ok(())
}

fn digest_matches(path: &Path, sha256: Option<&str>) -> Result<bool> {
    let Some(expected) = sha256 else {
        return Ok(true);
    };
    let mut hasher = Sha256::new();
    let mut file = fs::File::open(path)?;
    let mut buffer = vec![0u8; 1 << 20];
    loop {
        let read = file.read(&mut buffer)?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
    }
    Ok(hex::encode(hasher.finalize()).eq_ignore_ascii_case(expected))
}

struct SpeedMeter {
    window_start: Instant,
    window_bytes: u64,
    speed: u64,
}

impl SpeedMeter {
    fn new() -> Self {
        Self {
            window_start: Instant::now(),
            window_bytes: 0,
            speed: 0,
        }
    }

    fn update(&mut self, bytes: u64) -> u64 {
        let elapsed = self.window_start.elapsed();
        if elapsed >= Duration::from_secs(1) {
            self.speed =
                ((bytes.saturating_sub(self.window_bytes)) as f64 / elapsed.as_secs_f64()) as u64;
            self.window_start = Instant::now();
            self.window_bytes = bytes;
        }
        self.speed
    }
}

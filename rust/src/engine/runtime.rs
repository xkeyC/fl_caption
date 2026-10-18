//! Loading ONNX Runtime and the GPU libraries it needs, before any model.
//!
//! The infra crates build ort with `load-dynamic`: ONNX Runtime is opened on
//! first use from `ORT_DYLIB_PATH`. This module picks the library (the GPU
//! runtime package `runtime/ort/`, else the CPU one `runtime/ort-cpu/`, else a
//! developer's `runtime/runtime.txt`), puts its directory and the CUDA/cuDNN
//! directories first on the library search path and preloads the CUDA
//! libraries by full path, so an older copy elsewhere on PATH (CUDA 12.4's
//! cuBLAS, System32's onnxruntime.dll) is never picked.

use anyhow::{bail, Result};
use std::path::{Path, PathBuf};
use std::sync::OnceLock;

#[cfg(windows)]
pub const DYLIB_NAME: &str = "onnxruntime.dll";
#[cfg(not(windows))]
pub const DYLIB_NAME: &str = "libonnxruntime.so";

#[derive(Debug, Clone, Default)]
pub struct RuntimeState {
    pub ort_path: Option<PathBuf>,
    pub library_dirs: Vec<PathBuf>,
    /// The CUDA provider library sits beside ONNX Runtime (a GPU build).
    pub gpu_build: bool,
    pub error: Option<String>,
}

static STATE: OnceLock<RuntimeState> = OnceLock::new();

pub fn state() -> RuntimeState {
    STATE.get().cloned().unwrap_or_default()
}

/// Finds and prepares ONNX Runtime once per process; later calls return the
/// first result. `roots` are the directories searched for `runtime/` (the
/// executable's directory, the working directory).
pub fn init(roots: &[PathBuf]) -> RuntimeState {
    STATE
        .get_or_init(|| match prepare(roots) {
            Ok(state) => state,
            Err(error) => {
                tracing::error!(%error, "ONNX Runtime not available");
                RuntimeState {
                    error: Some(format!("{error:#}")),
                    ..RuntimeState::default()
                }
            }
        })
        .clone()
}

fn prepare(roots: &[PathBuf]) -> Result<RuntimeState> {
    let (dylib, mut dirs) = locate(roots)?;
    if let Some(parent) = dylib.parent() {
        dirs.insert(0, parent.to_path_buf());
    }
    dirs.dedup();
    #[cfg(windows)]
    let provider = "onnxruntime_providers_cuda.dll";
    #[cfg(not(windows))]
    let provider = "libonnxruntime_providers_cuda.so";
    let gpu_build = dylib
        .parent()
        .is_some_and(|dir| dir.join(provider).is_file());
    prepend_library_dirs(&dirs);
    if gpu_build {
        preload(&dirs);
    }
    std::env::set_var("ORT_DYLIB_PATH", &dylib);
    tracing::info!(path = %dylib.display(), gpu_build, dirs = ?dirs, "ONNX Runtime selected");
    Ok(RuntimeState {
        ort_path: Some(dylib),
        library_dirs: dirs,
        gpu_build,
        error: None,
    })
}

/// The library, and extra library directories (`lib=` lines of
/// runtime.txt).
fn locate(roots: &[PathBuf]) -> Result<(PathBuf, Vec<PathBuf>)> {
    if let Some(path) = std::env::var_os("ORT_DYLIB_PATH") {
        let path = PathBuf::from(path);
        if path.is_file() {
            return Ok((absolute(path), Vec::new()));
        }
        bail!("ORT_DYLIB_PATH names a missing file: {}", path.display());
    }
    for root in roots {
        let runtime = root.join("runtime");
        let txt = runtime.join("runtime.txt");
        if txt.is_file() {
            if let Some(found) = read_runtime_txt(&txt)? {
                return Ok(found);
            }
        }
        for sub in ["ort", "ort-cpu"] {
            let dylib = runtime.join(sub).join(DYLIB_NAME);
            if dylib.is_file() {
                return Ok((absolute(dylib), Vec::new()));
            }
        }
    }
    bail!(
        "{DYLIB_NAME} not found in runtime/ort or runtime/ort-cpu (searched {})",
        roots
            .iter()
            .map(|root| root.display().to_string())
            .collect::<Vec<_>>()
            .join(", ")
    )
}

/// `ort=<library>` and `lib=<directory>` lines (a developer's machine).
fn read_runtime_txt(path: &Path) -> Result<Option<(PathBuf, Vec<PathBuf>)>> {
    let text = std::fs::read_to_string(path)?;
    let mut ort = None;
    let mut libs = Vec::new();
    for line in text.lines().map(str::trim) {
        if let Some(value) = line.strip_prefix("ort=") {
            ort = Some(PathBuf::from(value.trim()));
        } else if let Some(value) = line.strip_prefix("lib=") {
            let dir = PathBuf::from(value.trim());
            if dir.is_dir() {
                libs.push(dir);
            } else {
                tracing::warn!(dir = %dir.display(), "runtime.txt names a missing directory");
            }
        }
    }
    Ok(ort
        .filter(|ort| ort.is_file())
        .map(|ort| (absolute(ort), libs)))
}

fn absolute(path: PathBuf) -> PathBuf {
    std::path::absolute(&path).unwrap_or(path)
}

#[cfg(windows)]
fn prepend_library_dirs(dirs: &[PathBuf]) {
    // LoadLibrary searches the process PATH as it is at call time: that is
    // how the CUDA provider finds cuDNN's sub-libraries. Remove other CUDA
    // toolkits' bin directories, whose older runtime would break the
    // provider if anything were loaded from them.
    let current = std::env::var_os("PATH").unwrap_or_default();
    let others = std::env::split_paths(&current).filter(|path| {
        let text = path.to_string_lossy().to_ascii_lowercase();
        !(text.contains("nvidia gpu computing toolkit") && text.contains("cuda"))
    });
    if let Ok(joined) = std::env::join_paths(dirs.iter().cloned().chain(others)) {
        std::env::set_var("PATH", joined);
    }
}

#[cfg(not(windows))]
fn prepend_library_dirs(dirs: &[PathBuf]) {
    // The loader reads LD_LIBRARY_PATH at start-up only; libraries are
    // preloaded by path instead. Kept for child processes (ffmpeg).
    let current = std::env::var_os("LD_LIBRARY_PATH").unwrap_or_default();
    if let Ok(joined) =
        std::env::join_paths(dirs.iter().cloned().chain(std::env::split_paths(&current)))
    {
        std::env::set_var("LD_LIBRARY_PATH", joined);
    }
}

/// What the CUDA provider links against, dependencies first.
#[cfg(windows)]
const PRELOAD: &[&str] = &[
    "cudart64_12.dll",
    "cublasLt64_12.dll",
    "cublas64_12.dll",
    "cufft64_11.dll",
    "nvrtc64_120_0.dll",
    "cudnn_graph64_9.dll",
    "cudnn64_9.dll",
];
#[cfg(not(windows))]
const PRELOAD: &[&str] = &[
    "libcudart.so.12",
    "libcublasLt.so.12",
    "libcublas.so.12",
    "libcufft.so.11",
    "libnvrtc.so.12",
    "libcudnn_graph.so.9",
    "libcudnn_engines_precompiled.so.9",
    "libcudnn_engines_runtime_compiled.so.9",
    "libcudnn_heuristic.so.9",
    "libcudnn_ops.so.9",
    "libcudnn_cnn.so.9",
    "libcudnn_adv.so.9",
    "libcudnn.so.9",
];

/// Loads each library from the first directory that has it: once loaded, a
/// library is what every later load of that name gets.
fn preload(dirs: &[PathBuf]) {
    #[cfg_attr(windows, allow(unused_mut))]
    let mut search = dirs.to_vec();
    #[cfg(not(windows))]
    {
        search.push(PathBuf::from("/usr/local/cuda/lib64"));
        search.push(PathBuf::from("/usr/lib/x86_64-linux-gnu"));
    }
    for name in PRELOAD {
        let Some(path) = search
            .iter()
            .map(|dir| dir.join(name))
            .find(|path| path.is_file())
        else {
            tracing::debug!(name, "not found for preloading");
            continue;
        };
        match load_library(&path) {
            Ok(()) => tracing::info!(path = %path.display(), "preloaded"),
            Err(error) => tracing::warn!(path = %path.display(), %error, "cannot preload"),
        }
    }
}

#[cfg(windows)]
fn load_library(path: &Path) -> std::io::Result<()> {
    use std::os::windows::ffi::OsStrExt;
    #[link(name = "kernel32")]
    extern "system" {
        fn LoadLibraryExW(
            name: *const u16,
            file: *mut std::ffi::c_void,
            flags: u32,
        ) -> *mut std::ffi::c_void;
    }
    const LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR: u32 = 0x100;
    const LOAD_LIBRARY_SEARCH_DEFAULT_DIRS: u32 = 0x1000;
    let wide: Vec<u16> = path
        .as_os_str()
        .encode_wide()
        .chain(std::iter::once(0))
        .collect();
    // SAFETY: a NUL-terminated wide path; the library stays loaded for the
    // process, as the provider that uses it does.
    let module = unsafe {
        LoadLibraryExW(
            wide.as_ptr(),
            std::ptr::null_mut(),
            LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS,
        )
    };
    if module.is_null() {
        Err(std::io::Error::last_os_error())
    } else {
        Ok(())
    }
}

#[cfg(not(windows))]
fn load_library(path: &Path) -> std::io::Result<()> {
    use std::os::unix::ffi::OsStrExt;
    let mut bytes = path.as_os_str().as_bytes().to_vec();
    bytes.push(0);
    // SAFETY: a NUL-terminated path; the handle is never closed.
    let handle = unsafe {
        libc::dlopen(
            bytes.as_ptr() as *const libc::c_char,
            libc::RTLD_NOW | libc::RTLD_GLOBAL,
        )
    };
    if handle.is_null() {
        // SAFETY: dlerror returns a static, NUL-terminated message.
        let message = unsafe { std::ffi::CStr::from_ptr(libc::dlerror()) };
        Err(std::io::Error::other(
            message.to_string_lossy().into_owned(),
        ))
    } else {
        Ok(())
    }
}

#[derive(Debug, Clone)]
pub struct Gpu {
    pub name: String,
    pub total_mb: u64,
    pub used_mb: u64,
    pub driver: String,
}

/// NVIDIA GPUs through NVML (the driver's library); empty without one.
pub fn gpus() -> Vec<Gpu> {
    static NVML: OnceLock<Option<nvml_wrapper::Nvml>> = OnceLock::new();
    let Some(nvml) = NVML.get_or_init(|| nvml_wrapper::Nvml::init().ok()) else {
        return Vec::new();
    };
    let driver = nvml.sys_driver_version().unwrap_or_default();
    let count = nvml.device_count().unwrap_or(0);
    (0..count)
        .filter_map(|index| {
            let device = nvml.device_by_index(index).ok()?;
            let memory = device.memory_info().ok()?;
            Some(Gpu {
                name: device.name().unwrap_or_else(|_| format!("GPU {index}")),
                total_mb: memory.total / (1024 * 1024),
                used_mb: memory.used / (1024 * 1024),
                driver: driver.clone(),
            })
        })
        .collect()
}

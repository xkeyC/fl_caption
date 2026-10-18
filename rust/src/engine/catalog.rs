//! The models fl_caption offers, all run by local-multimodal-infra adapters.
//!
//! Upstream files are pinned by URL, size and SHA-256 (as in infra's
//! `configs/providers`). The exports of local-multimodal-infra (the GPU int8
//! SenseVoice, Fun-ASR-Nano, the int4 chat models) are published as complete
//! packages, one Hugging Face repository each, and listed through the Hub API
//! at a pinned revision; until one is published it can be imported from a
//! local directory.

use serde_json::{json, Map, Value};

/// A published package: every file of `repo` at `revision`.
#[derive(Debug, Clone, Copy)]
pub struct Hosted {
    pub repo: &'static str,
    /// `None` until the repository is published.
    pub revision: Option<&'static str>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ModelKind {
    Asr,
    Translator,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Engine {
    SenseVoice,
    FunAsrNano,
    /// A dedicated translation model with Hy-MT2's prompt templates.
    HyMt,
    /// A general instruction model (system prompt, chat history).
    ChatLlm,
}

#[derive(Debug, Clone, Copy)]
pub struct UrlFile {
    /// Path inside the model directory.
    pub path: &'static str,
    pub url: &'static str,
    pub sha256: &'static str,
    pub size: u64,
}

#[derive(Debug, Clone)]
pub struct CatalogEntry {
    pub id: &'static str,
    pub name: &'static str,
    pub kind: ModelKind,
    pub engine: Engine,
    pub description_zh: &'static str,
    pub description_en: &'static str,
    /// Download size.
    pub size_mb: u64,
    /// GPU memory the loaded model takes beside the CUDA context, at the
    /// default context for chat models: NVML deltas on an RTX 4090 (ORT 1.31
    /// CUDA 12) less the context, peaks of `examples/bench.rs` runs.
    pub vram_mb: u64,
    /// Host memory when it runs on the CPU (or for its CPU parts).
    pub ram_mb: u64,
    /// KV cache per context token (chat models), for the VRAM estimate.
    pub kv_kb_per_token: u64,
    pub default_context: u64,
    pub gpu_only: bool,
    /// Runs reasonably on the CPU (otherwise CPU is only a fallback).
    pub cpu_ok: bool,
    pub hotwords: bool,
    pub languages: &'static str,
    pub license: &'static str,
    pub homepage: &'static str,
    /// Upstream files.
    pub files: &'static [UrlFile],
    /// The published package (instead of upstream files).
    pub hosted: Option<Hosted>,
    /// Shown first in its kind.
    pub recommended: bool,
}

impl CatalogEntry {
    /// The adapter metadata of infra's model spec for this model.
    pub fn metadata(&self) -> Map<String, Value> {
        let value = match self.id {
            "sensevoice-small-onnx" => json!({
                "vad_max_segment_seconds": 20,
                "vad_provider_order": ["cpu"],
                "speaker_provider_order": ["cpu"],
                "speaker_batch_size": 32,
            }),
            "sensevoice-small-int8-gpu-onnx" => json!({
                "asr_model_file": "model_gpu_int8.onnx",
                "vad_max_segment_seconds": 20,
                "asr_cuda_graph_frames": [64, 128, 256, 352],
                "vad_provider_order": ["cpu"],
                "speaker_provider_order": ["cpu"],
                "speaker_batch_size": 32,
            }),
            "fun-asr-nano-onnx" => json!({
                "vad_max_segment_seconds": 20,
                "asr_cuda_graph_frames": [64, 128, 256, 352],
                "max_context": 1024,
                "ctc_guard": true,
                "vad_provider_order": ["cpu"],
                "speaker_provider_order": ["cpu"],
                "speaker_batch_size": 32,
            }),
            _ => json!({}),
        };
        match value {
            Value::Object(map) => map,
            _ => Map::new(),
        }
    }

    pub fn adapter(&self) -> &'static str {
        match self.engine {
            Engine::SenseVoice => "sense_voice_asr",
            Engine::FunAsrNano => "fun_asr_nano",
            Engine::HyMt | Engine::ChatLlm => "qwen3_chat",
        }
    }

    pub fn downloadable(&self) -> bool {
        self.hosted.is_none_or(|hosted| hosted.revision.is_some())
    }

    /// GPU memory at `context` tokens (chat models) or as loaded (ASR).
    pub fn vram_at(&self, context: u64) -> u64 {
        self.vram_mb + self.kv_kb_per_token * context.saturating_sub(self.default_context) / 1024
    }
}

/// SenseVoice's frontend, FSMN-VAD and CAM++ (infra's pipeline loads all
/// three): shared by every FunASR-family package.
const FUNASR_PIPELINE: [UrlFile; 7] = [
    UrlFile {
        path: "asr/am.mvn",
        url: "https://huggingface.co/haixuantao/SenseVoiceSmall-onnx/resolve/c4c8747214bed7ebbf2557e0412c19efa540023c/am.mvn?download=true",
        sha256: "29b3c740a2c0cfc6b308126d31d7f265fa2be74f3bb095cd2f143ea970896ae5",
        size: 11203,
    },
    UrlFile {
        path: "asr/config.yaml",
        url: "https://huggingface.co/haixuantao/SenseVoiceSmall-onnx/resolve/c4c8747214bed7ebbf2557e0412c19efa540023c/config.yaml?download=true",
        sha256: "f71e239ba36705564b5bf2d2ffd07eece07b8e3f2bbf6d2c99d8df856339ac19",
        size: 1855,
    },
    UrlFile {
        path: "asr/tokens.json",
        url: "https://huggingface.co/haixuantao/SenseVoiceSmall-onnx/resolve/c4c8747214bed7ebbf2557e0412c19efa540023c/tokens.json?download=true",
        sha256: "a2594fc1474e78973149cba8cd1f603ebed8c39c7decb470631f66e70ce58e97",
        size: 352064,
    },
    UrlFile {
        path: "vad/model_quant.onnx",
        url: "https://huggingface.co/funasr/fsmn-vad-onnx/resolve/f6e9fbb4cefa7397216c763f21307993f147f585/model_quant.onnx?download=true",
        sha256: "9b28837838fce9685503c63139fadbad35d6c8ed485485dafdbb32e725969660",
        size: 508876,
    },
    UrlFile {
        path: "vad/am.mvn",
        url: "https://huggingface.co/funasr/fsmn-vad-onnx/resolve/f6e9fbb4cefa7397216c763f21307993f147f585/vad.mvn?download=true",
        sha256: "6820fef9687708c4fc3fab2530179c8fcea6262daa25514380056cd8f6eb1754",
        size: 8040,
    },
    UrlFile {
        path: "vad/config.yaml",
        url: "https://huggingface.co/MoYoYoTech/Translator/resolve/58fbad4088820ed1253955c8faf1444cd0b2dc69/moyoyo_asr_models/speech_fsmn_vad_zh-cn-16k-common-pytorch/config.yaml?download=true",
        sha256: "486861ca26ddb79081663b6179cb204c6bfae71c52f04aafc48a9e9d8dde1e93",
        size: 1215,
    },
    UrlFile {
        path: "speaker/campplus_cn_en_common_200k.onnx",
        url: "https://huggingface.co/welcomyou/campplus-3dspeaker-200k-onnx/resolve/6265ff7af2a104d745b4389026ed9815c6c1c6ff/campplus_cn_en_common_200k.onnx",
        sha256: "dd1740aa1e1ffa3895f96aef2166b8af2bb2ad09c00769dd275ee36aef6a2a7f",
        size: 28283928,
    },
];

const SENSEVOICE_CPU_FILES: [UrlFile; 8] = [
    UrlFile {
        path: "asr/model_quant.onnx",
        url: "https://huggingface.co/haixuantao/SenseVoiceSmall-onnx/resolve/c4c8747214bed7ebbf2557e0412c19efa540023c/model_quant.onnx?download=true",
        sha256: "21dc965f689a78d1604717bf561e40d5a236087c85a95584567835750549e822",
        size: 241216270,
    },
    FUNASR_PIPELINE[0],
    FUNASR_PIPELINE[1],
    FUNASR_PIPELINE[2],
    FUNASR_PIPELINE[3],
    FUNASR_PIPELINE[4],
    FUNASR_PIPELINE[5],
    FUNASR_PIPELINE[6],
];

pub fn catalog() -> Vec<CatalogEntry> {
    vec![
        CatalogEntry {
            id: "sensevoice-small-int8-gpu-onnx",
            name: "SenseVoice Small (GPU)",
            kind: ModelKind::Asr,
            engine: Engine::SenseVoice,
            description_zh: "低延迟实时识别：全程在 GPU 上运行并使用 CUDA graph，1.5 秒语音约 16 ms。识别语言、情绪与声音事件。",
            description_en: "Low-latency live recognition, entirely on the GPU with CUDA graphs: ~16 ms for 1.5 s of speech. Detects language, emotion and sound events.",
            size_mb: 540,
            vram_mb: 1050,
            ram_mb: 900,
            kv_kb_per_token: 0,
            default_context: 0,
            gpu_only: false,
            cpu_ok: false,
            hotwords: false,
            languages: "zh, en, yue, ja, ko",
            license: "FunASR Model License",
            homepage: "https://huggingface.co/FunAudioLLM/SenseVoiceSmall",
            files: &[],
            hosted: Some(Hosted {
                repo: "ModaLeap/sensevoice-small-onnx",
                revision: Some("f9ce3be8f1d08eef33a3d1480c3c584599fefbbe"),
            }),
            recommended: true,
        },
        CatalogEntry {
            id: "fun-asr-nano-onnx",
            name: "Fun-ASR-Nano",
            kind: ModelKind::Asr,
            engine: Engine::FunAsrNano,
            description_zh: "更准确的识别（SenseVoice 编码器 + Qwen3-0.6B），支持热词，中英混说更好；1.5 秒语音约 30–45 ms。仅 GPU。",
            description_en: "More accurate (SenseVoice encoder + Qwen3-0.6B) with hotwords and better code-switching; ~30-45 ms for 1.5 s. GPU only.",
            size_mb: 1330,
            vram_mb: 2180,
            ram_mb: 1500,
            kv_kb_per_token: 0,
            default_context: 0,
            gpu_only: true,
            cpu_ok: false,
            hotwords: true,
            languages: "zh, en, ja",
            license: "Apache-2.0",
            homepage: "https://modelscope.cn/models/FunAudioLLM/Fun-ASR-Nano-2512",
            files: &[],
            hosted: Some(Hosted {
                repo: "ModaLeap/fun-asr-nano-onnx",
                revision: Some("563e2395ddd8d963343f2f0ac4c256245fc9957c"),
            }),
            recommended: false,
        },
        CatalogEntry {
            id: "sensevoice-small-onnx",
            name: "SenseVoice Small (CPU)",
            kind: ModelKind::Asr,
            engine: Engine::SenseVoice,
            description_zh: "无需显卡：动态 INT8，在 CPU 上运行。适合没有 NVIDIA 显卡的电脑与音视频文件转写。",
            description_en: "No GPU needed: dynamic INT8 on the CPU. For computers without an NVIDIA GPU and for file transcription.",
            size_mb: 258,
            vram_mb: 0,
            ram_mb: 1200,
            kv_kb_per_token: 0,
            default_context: 0,
            gpu_only: false,
            cpu_ok: true,
            hotwords: false,
            languages: "zh, en, yue, ja, ko",
            license: "Apache-2.0",
            homepage: "https://huggingface.co/haixuantao/SenseVoiceSmall-onnx",
            files: &SENSEVOICE_CPU_FILES,
            hosted: None,
            recommended: false,
        },
        CatalogEntry {
            id: "hy-mt2-1.8b-int4-onnx",
            name: "Hy-MT2 1.8B",
            kind: ModelKind::Translator,
            engine: Engine::HyMt,
            description_zh: "腾讯混元翻译模型：33 种语言互译，支持术语表与背景信息，体积小、速度快。推荐用于实时字幕。",
            description_en: "Tencent Hunyuan translation model: 33 languages, glossary and background aware, small and fast. Recommended for live captions.",
            size_mb: 1080,
            vram_mb: 2100,
            ram_mb: 2500,
            kv_kb_per_token: 64,
            default_context: 4096,
            gpu_only: false,
            cpu_ok: false,
            hotwords: false,
            languages: "33",
            license: "Apache-2.0",
            homepage: "https://huggingface.co/tencent/Hy-MT2-1.8B",
            files: &[],
            hosted: Some(Hosted {
                repo: "ModaLeap/hy-mt2-1.8b-onnx",
                revision: Some("a1d884fcf0f5ec65f4043bb353de76f12c597dca"),
            }),
            recommended: true,
        },
        CatalogEntry {
            id: "qwen3-4b-instruct-2507-int4-onnx",
            name: "Qwen3 4B Instruct 2507",
            kind: ModelKind::Translator,
            engine: Engine::ChatLlm,
            description_zh: "通用大模型：可按自定义提示词翻译、润色并修正识别错误，显存占用更高。",
            description_en: "General LLM: follows custom prompts, polishes and fixes recognition errors; needs more GPU memory.",
            size_mb: 2700,
            vram_mb: 4100,
            ram_mb: 4500,
            kv_kb_per_token: 144,
            default_context: 4096,
            gpu_only: false,
            cpu_ok: false,
            hotwords: false,
            languages: "100+",
            license: "Apache-2.0",
            homepage: "https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507",
            files: &[],
            hosted: Some(Hosted {
                repo: "ModaLeap/qwen3-4b-instruct-2507-onnx",
                revision: Some("9edf4d82358af91d00e028f891f8a23ce738d997"),
            }),
            recommended: false,
        },
    ]
}

pub fn find(id: &str) -> Option<CatalogEntry> {
    catalog().into_iter().find(|entry| entry.id == id)
}

/// GPU memory the CUDA context and ONNX Runtime take once, whatever runs.
pub const CUDA_CONTEXT_MB: u64 = 300;

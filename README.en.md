# FL Caption

[中文](README.md) | English

Offline live captions and translation: it captions what the computer plays or the microphone hears as it is spoken, translates it into your language, and turns audio/video files into subtitle or lyrics files. Multimodal inference is built on [local-multimodal-infra](https://github.com/mercallureAI/local-multimodal-infra): every model runs locally on ONNX Runtime; translation can also go through any OpenAI-compatible API.

## Features

- **Captions as they are spoken**: the line being spoken refreshes every ~0.4 s (10–30 ms per recognition on a GPU), anchored left and only growing at its end; the final line ~0.45 s after a pause.
- **Live translation**: local models reuse the previous line's KV cache (~0.1 s per line), lines being spoken are translated too; or any OpenAI-compatible API.
- **Hotwords and glossary**: terms with translations guide the translator; terms marked as hotwords bias Fun-ASR-Nano; correction rules for recognition errors.
- **Files to subtitles / lyrics**: SRT, VTT, LRC, TXT, bilingual; whole sentences translated, then split back over their cues.
- **Caption bar + settings window**: a transparent always-on-top bar (click-through lock, tray), hover tools to clear or export the context (last 10 000 lines with times), settings in their own window.
- **Model manager**: GPU/RAM use per model and for the current selection, downloads (with a Hugging Face mirror) and imports of exported directories.

## Install

Unpack into one folder: `fl_caption-v<version>-<os>-x64` (the program and the CPU ONNX Runtime) and, for NVIDIA GPUs (driver 550+), `fl_caption-runtime-cuda-v<version>-<os>-x64` (ONNX Runtime 1.31 CUDA 12, the CUDA 12.8 runtime, cuDNN 9). Models are downloaded from the app.

## Models (RTX 4090, plus ~0.3 GB CUDA context)

| Model | Use | GPU memory |
|---|---|---|
| SenseVoice Small (GPU) | speech, ~16 ms per 1.5 s | ≈ 1.0 GB |
| Fun-ASR-Nano | speech, hotwords, GPU only | ≈ 2.2 GB |
| SenseVoice Small (CPU) | speech without a GPU | 0 |
| Hy-MT2 1.8B | translation, 33 languages (default) | ≈ 2.1 GB |
| Qwen3 4B Instruct 2507 | translation, general LLM | ≈ 4.1 GB |

On 100 FLEURS sentences Hy-MT2 and Qwen3 score alike (chrF en→zh 36.1 vs 34.2, zh→en 55.5 vs 54.7; glossary 16/16 each); Hy-MT2 needs half the memory, Qwen3 reads more naturally on casual speech.

## Build

Flutter 3.47, Rust 1.92+, and the local-multimodal-infra dependency (`main`) checked out beside this repository (a path dependency). Then `python scripts/fetch_onnxruntime.py`, `flutter build windows --release` (or `linux`), `python scripts/package_release.py`. See the Chinese README for the details and `rust/examples/bench.rs` for real-model checks.

## License

[AGPL-3.0](LICENSE)

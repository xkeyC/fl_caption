# FL Caption

中文 | [English](README.en.md)

离线的实时字幕与翻译工具：识别电脑正在播放的声音或麦克风，边说边出字幕，并实时翻译成你的语言；也能把音视频文件转成字幕或歌词文件。多模态推理基于 [local-multimodal-infra](https://github.com/mercallureAI/local-multimodal-infra) 实现，所有模型都在本机通过 ONNX Runtime 运行；翻译也可以改用任意 OpenAI 兼容接口。

演示视频（旧版）：https://www.bilibili.com/video/BV1VyQtYMEWA · QQ 群：1037016702

## 特性

- **边说边出的字幕**：说话期间每约 0.4 秒刷新一次正在说的句子，文字只在末尾增长、左对齐、位置固定；停顿后约 0.45 秒给出定稿。GPU 上每次识别 10–30 ms。
- **实时翻译**：本地翻译模型复用上一句的 KV 缓存，只计算新增的部分，一句约 0.1 秒；正在说的句子也会边说边翻。可改用 DeepSeek、OpenAI、Ollama、LM Studio 等 OpenAI 兼容接口。
- **热词与术语表**：术语表提示给翻译模型（含译法），勾选为热词的词条交给 Fun-ASR-Nano 提高识别率；另有识别纠错规则。
- **文件转字幕 / 歌词**：音视频文件 → SRT、VTT、LRC、TXT，可输出双语；按整句翻译后再按时间轴拆回每条字幕，长句按标点和词边界（中文用 jieba）断行。
- **字幕条 + 设置窗口**：透明置顶的字幕条可锁定为鼠标穿透（托盘解锁），悬停可开始/停止、清理或导出上下文（内存中保留最近 1 万句及时间）；设置在独立窗口中。
- **模型管理**：标注每个模型的显存与内存占用，按当前选择估算总显存；支持应用内下载（含 Hugging Face 镜像）和导入本地导出的模型目录。

## 系统要求

| | 要求 |
|---|---|
| 系统 | Windows 10/11 x64；Linux x64（PipeWire） |
| GPU 加速 | NVIDIA 显卡，驱动 550 或更新；显存见下表（翻译 + 识别约 3.5 GB 起） |
| 无 NVIDIA 显卡 | 可用 CPU 版 SenseVoice 识别 + 在线 API 翻译 |

## 下载与安装

在 [Releases](../../releases) 下载后**解压到同一个文件夹**：

| 文件 | 内容 | 需要吗 |
|---|---|---|
| `fl_caption-v<版本>-windows-x64.zip` | 程序和 CPU 版 ONNX Runtime | 必需 |
| `fl_caption-runtime-cuda-v<版本>-windows-x64.zip` | `runtime/ort/`：ONNX Runtime 1.31（CUDA 12）、CUDA 12.8 运行库、cuDNN 9 | 使用 NVIDIA 显卡时需要 |

模型在应用的「模型」页下载（或导入），默认放在用户数据目录，程序目录下有 `models/` 时优先用它。运行库很少变化，升级时通常只需更换程序包。

## 使用

1. 运行 `fl_caption.exe`。首次启动会打开设置窗口的「模型」页：下载一个语音识别模型和一个翻译模型（或在「翻译」页填写 API）。
2. 在「实时字幕」页选择声音来源（系统声音 / 麦克风），点「开始字幕」。
3. 字幕条可拖动、拖边缘调整大小；悬停显示工具：开始/停止、锁定（鼠标穿透）、清理上下文、导出上下文、设置、退出。锁定后从托盘图标解锁。
4. 「文件」页：拖入音视频文件，选择格式（LRC 为歌词）与单语/双语，生成的文件保存在源文件旁或指定目录。

左下角显示 ASR 延迟、翻译延迟和缓冲占用（当前这句已说的时长 / 单句最长）。

## 模型

显存为 RTX 4090 实测（ONNX Runtime 1.31 CUDA 12），另需约 0.3 GB 的 CUDA 上下文，翻译模型按 4K 上下文计。

| 模型 | 用途 | 显存 | 说明 |
|---|---|---|---|
| SenseVoice Small (GPU) | 识别 | ≈ 1.0 GB | 全程 GPU + CUDA graph，1.5 秒语音约 16 ms；识别语言、情绪；推荐 |
| Fun-ASR-Nano | 识别 | ≈ 2.2 GB | 更准，支持热词与中英混说；仅 GPU |
| SenseVoice Small (CPU) | 识别 | 0 | 无显卡也能用 |
| Hy-MT2 1.8B | 翻译 | ≈ 2.1 GB | 腾讯混元翻译模型，33 种语言，支持术语与背景信息；推荐 |
| Qwen3 4B Instruct 2507 | 翻译 | ≈ 4.1 GB | 通用大模型，口语更自然，可按自定义提示词润色与纠错 |

### 翻译模型对比

同一批 100 句 FLEURS（已排除政治、宗教、灾难等题材）与一组游戏语音术语句，贪心解码、4 句上下文，RTX 4090：

| | Hy-MT2 1.8B | Qwen3 4B |
|---|---|---|
| chrF 英→中 / 中→英 | 36.1 / 55.5 | 34.2 / 54.7 |
| 术语表命中 | 16/16 | 16/16 |
| 每句平均 / 首字 | 168 ms / 13 ms | 145 ms / 15 ms |
| KV 前缀复用 | 64% | 83% |
| 显存（加载后，不含识别） | +2.4 GB | +4.1 GB |

两者质量接近：Hy-MT2 在书面句子上略好、显存少近一半；Qwen3 口语更自然（如“我开星际农夫，你开大黄蜂”），专有名词也更稳。默认使用 Hy-MT2。

## 常见问题

- **模型下载慢**：在「模型」页把下载源切换为 hf-mirror.com。
- **没有用上 GPU**：确认已解压 GPU 运行库到程序目录（`runtime/ort/`），「模型」页会显示「GPU 运行库已就绪」；日志在「关于」页列出的路径。
- **电脑音量很小时识别不到**：在「实时字幕 → 高级」中打开「弱音增强」。
- **某些格式无法读取**：常见音视频（MP4/M4A/MP3/FLAC/WAV/OGG/MKV 中的 AAC 等）直接支持；其他格式会调用 ffmpeg（放在程序目录或 PATH 中）。

## 从源码构建

需要 Flutter 3.47、Rust 1.92+，以及作为依赖引用的 local-multimodal-infra：与本仓库**并列**检出（`main` 分支；`rust/Cargo.toml` 以路径引用）：

```
workspace/
├─ fl_caption/
└─ local-multimodal-infra/
```

```bash
python scripts/fetch_onnxruntime.py        # runtime/ort（CUDA 12）与 runtime/ort-cpu
flutter build windows --release            # Linux：flutter build linux --release
python scripts/package_release.py          # dist/：程序包与 GPU 运行库包
```

- 开发时可在 `runtime/runtime.txt` 中用 `ort=<onnxruntime.dll>` 与 `lib=<CUDA/cuDNN 目录>` 指定本机的运行库。
- Rust 改动后：`flutter_rust_bridge_codegen generate` 重新生成绑定。
- 真实模型测试（`rust/examples/bench.rs`）：`file`（文件转字幕）、`live`（按真实速度把音频送入实时管线）、`translate`（翻译质量与延迟），用法见文件开头。
- 应用下载的模型是 local-multimodal-infra 导出、发布在 Hugging Face [ModaLeap](https://huggingface.co/ModaLeap) 组织的模型包（每个模型一个仓库），`rust/src/engine/catalog.rs` 固定各仓库的 `revision`。

## 致谢

多模态推理基于 [local-multimodal-infra](https://github.com/mercallureAI/local-multimodal-infra) 实现，并使用了 [ONNX Runtime](https://github.com/microsoft/onnxruntime)、[ort](https://github.com/pykeio/ort)、[SenseVoice](https://github.com/FunAudioLLM/SenseVoice)、[Fun-ASR](https://github.com/QwenAudio/Fun-ASR)、[Hy-MT2](https://github.com/Tencent-Hunyuan/Hy-MT2)、[Qwen3](https://github.com/QwenLM/Qwen3)、[Silero VAD](https://github.com/snakers4/silero-vad)、[jieba-rs](https://github.com/messense/jieba-rs)、[flutter_rust_bridge](https://github.com/fzyzcjy/flutter_rust_bridge)、[fluent_ui](https://github.com/bdlukaa/fluent_ui)。各模型沿用其上游许可证。

## 许可证

[AGPL-3.0](LICENSE)

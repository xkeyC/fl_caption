# FL Caption

演示视频：https://www.bilibili.com/video/BV1VyQtYMEWA

离线实时字幕软件，使用 Flutter 和 Rust 编写，由基于 candle 推理框架的 Whisper 和 LLM 驱动。

![image.png](https://s2.loli.net/2025/03/15/5PbgI1WYapKt4jR.png)


## 使用说明

1. 通过 Release 下载压缩包并解压：https://github.com/xkeyC/fl_caption/releases

2. 首次使用请点击设置图标，选择合适的语音模型，并点击下载按钮

3. 下载成功后请选择语音语言与字幕语言，并设置 llm api 信息，完成后点击保存

4. 字幕应当会正常开始运行。

## 常见问题

1. 模型下载无进度或下载失败：请尝试参照 https://github.com/xkeyC/fl_caption/issues/1 设置 `HF_ENDPOINT` 环境变量，或打开 https://github.com/xkeyC/fl_caption/blob/main/lib/common/whisper/models.dart 的链接手动下载文件，文件名即为 name 的值，如 `base` `large-v3_q4k` 等。
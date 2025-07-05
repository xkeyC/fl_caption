import 'models.dart';

class OnnxModelsData extends WhisperModelData {
  final String onnxExecMode;

  const OnnxModelsData({
    required super.name,
    required super.size,
    required super.sizeInt,
    required super.isMultilingual,
    required super.downloadUrls,
    super.isQuantized = true,
    super.configType = WhisperModelConfigType.onnx,
    required this.onnxExecMode,
  });

  static const Map<String, OnnxModelsData> onnxModels = {
    // sense-voice
    "Sense-Voice-2024-07-17": OnnxModelsData(
      name: 'Sense-Voice-2024-07-17',
      size: '239 MB',
      sizeInt: 239 * 1024,
      isMultilingual: true,
      downloadUrls: {
        "Sense-Voice-2024-07-17_model.int8.onnx":
            "https://huggingface.co/xkeyC/fl_caption_onnx_models/resolve/main/sense-voice-2024-07-17/model.int8.onnx",
      },
      onnxExecMode: 'sense-voice',
    ),
    // whisper-large-v3-turbo
    "whisper-large-v3-turbo-CUDA": OnnxModelsData(
      name: 'whisper-large-v3-turbo-CUDA',
      size: '1.63 GB',
      sizeInt: 1630 * 1024,
      isMultilingual: true,
      downloadUrls: {
        "whisper-large-v3-turbo_model_gpu_fp16.onnx":
            "https://huggingface.co/xkeyC/whisper-large-v3-turbo-gguf/resolve/main/model_gpu_fp16.onnx",
      },
      onnxExecMode: 'whisper-olive',
    ),
  };
}

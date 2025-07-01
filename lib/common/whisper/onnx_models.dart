import 'models.dart';

class OnnxModelsData extends WhisperModelData {
  final String onnxExecMode;

  const OnnxModelsData({
    required super.name,
    required super.size,
    required super.sizeInt,
    required super.isMultilingual,
    required super.downloadUrl,
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
      downloadUrl:
          'https://huggingface.co/xkeyC/fl_caption_onnx_models/resolve/main/sense-voice-2024-07-17/model.int8.onnx',
      onnxExecMode: 'sense-voice',
    ),
  };
}

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
        "Sense-Voice-2024-07-17":
            "'https://huggingface.co/xkeyC/fl_caption_onnx_models/resolve/main/sense-voice-2024-07-17/model.int8.onnx'",
      },
      onnxExecMode: 'sense-voice',
    ),
    // whisper-large-v3-turbo
    "whisper-large-v3-turbo": OnnxModelsData(
      name: 'whisper-large-v3-turbo',
      size: '751 MB',
      sizeInt: 751 * 1024,
      isMultilingual: true,
      downloadUrls: {
        "decoder_with_past_model_q4.onnx":
            "https://huggingface.co/onnx-community/whisper-large-v3-turbo/resolve/main/onnx/decoder_with_past_model_q4.onnx",
        "encoder_model_q4.onnx":
            "https://huggingface.co/onnx-community/whisper-large-v3-turbo/resolve/main/onnx/encoder_model_q4.onnx",
      },
      onnxExecMode: 'whisper',
    ),
  };
}

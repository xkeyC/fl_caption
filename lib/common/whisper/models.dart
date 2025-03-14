import 'dart:io';

/// Models for the Whisper API
class WhisperModelData {
  final String name;
  final String size;

  /// Size in kb
  final int sizeInt;
  final bool isMultilingual;
  final bool isQuantized;
  final String downloadUrl;

  const WhisperModelData({
    required this.name,
    required this.size,
    required this.sizeInt,
    required this.isMultilingual,
    required this.isQuantized,
    required this.downloadUrl,
  });

  String getDownloadUrl() {
    // check HF_ENDPOINT environment variable
    final hfEndpoint = Platform.environment['HF_ENDPOINT'];
    if (hfEndpoint != null && hfEndpoint.isNotEmpty) {
      return downloadUrl.replaceFirst('https://huggingface.co', hfEndpoint);
    }
    return downloadUrl;
  }
}

const Map<String, WhisperModelData> whisperModels = {
  "base": WhisperModelData(
    name: 'base',
    size: '290Mb',
    sizeInt: 290 * 1024,
    isMultilingual: true,
    isQuantized: false,
    downloadUrl: 'https://huggingface.co/openai/whisper-base/resolve/main/model.safetensors',
  ),
  "medium_q4k": WhisperModelData(
    name: 'medium_q4k',
    size: '444 MB',
    sizeInt: 444 * 1024,
    isMultilingual: true,
    isQuantized: true,
    downloadUrl: 'https://huggingface.co/OllmOne/whisper-medium-GGUF/resolve/main/model-q4k.gguf',
  ),
  "large-v3_q4k": WhisperModelData(
    name: 'large-v3_q4k',
    size: '891Mb',
    sizeInt: 891 * 1024,
    isMultilingual: true,
    isQuantized: true,
    downloadUrl: 'https://huggingface.co/OllmOne/whisper-large-v3-GGUF/resolve/main/model-q4k.gguf',
  ),
};

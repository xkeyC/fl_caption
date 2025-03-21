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
    size: '290 MB',
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
  "large-v2": WhisperModelData(
    name: 'large-v2',
    size: '5.75 GB',
    sizeInt: 5750 * 1024,
    isMultilingual: true,
    isQuantized: false,
    downloadUrl: 'https://huggingface.co/openai/whisper-large-v2/resolve/main/model.safetensors',
  ),
  "large-v2_q4_k": WhisperModelData(
    name: 'large-v2_q4_k',
    size: '890 MB',
    sizeInt: 890 * 1024,
    isMultilingual: true,
    isQuantized: true,
    downloadUrl: 'https://huggingface.co/xkeyC/whisper-large-v2-gguf/resolve/main/model_q4_k.gguf',
  ),
  "large-v3_q4k": WhisperModelData(
    name: 'large-v3_q4k',
    size: '891 Mb',
    sizeInt: 891 * 1024,
    isMultilingual: true,
    isQuantized: true,
    downloadUrl: 'https://huggingface.co/OllmOne/whisper-large-v3-GGUF/resolve/main/model-q4k.gguf',
  ),
  "large-v3-turbo": WhisperModelData(
    name: 'large-v3-turbo',
    size: '1.62 Gb',
    sizeInt: 1620 * 1024,
    isMultilingual: true,
    isQuantized: false,
    downloadUrl: 'https://huggingface.co/openai/whisper-large-v3-turbo/resolve/main/model.safetensors',
  ),
  "large-v3-turbo_q4_k": WhisperModelData(
    name: 'large-v3-turbo_q4_k',
    size: '476 MB',
    sizeInt: 476 * 1024,
    isMultilingual: true,
    isQuantized: true,
    downloadUrl: 'https://huggingface.co/xkeyC/whisper-large-v3-turbo-gguf/resolve/main/model_q4_k.gguf',
  ),
};

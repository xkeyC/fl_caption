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
}

const Map<String, WhisperModelData> whisperModels = {
  "base": WhisperModelData(
    name: 'base',
    size: '290Mb',
    sizeInt: 290 * 1024,
    isMultilingual: true,
    isQuantized: false,
    downloadUrl:
        'https://huggingface.co/openai/whisper-base/resolve/main/model.safetensors',
  ),
  "large-v3_q4k": WhisperModelData(
    name: 'large-v3_q4k',
    size: '891Mb',
    sizeInt: 891 * 1024,
    isMultilingual: true,
    isQuantized: true,
    downloadUrl:
        'https://huggingface.co/OllmOne/whisper-large-v3-GGUF/resolve/main/model-q4k.gguf',
  ),
};

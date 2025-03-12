/// Models for the Whisper API
class WhisperModelData {
  final String name;
  final String size;
  final bool isMultilingual;
  final bool isQuantized;
  final String downloadUrl;

  const WhisperModelData({
    required this.name,
    required this.size,
    required this.isMultilingual,
    required this.isQuantized,
    required this.downloadUrl,
  });
}

const Map<String, WhisperModelData> whisperModels = {
  "base": WhisperModelData(
    name: 'base',
    size: '290Mb',
    isMultilingual: true,
    isQuantized: false,
    downloadUrl:
        'https://huggingface.co/openai/whisper-base/resolve/main/model.safetensors',
  ),
};

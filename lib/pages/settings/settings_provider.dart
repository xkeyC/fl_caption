import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'settings_provider.g.dart';

part 'settings_provider.freezed.dart';

@freezed
abstract class AppSettingsData with _$AppSettingsData {
  factory AppSettingsData({
    required String modelWorkingDir,
    required String whisperModel,
    required bool tryWithCuda,
    required bool withVAD,
    required double vadThreshold,
    required String llmProviderUrl,
    required String llmProviderKey,
    required String llmProviderModel,
    required bool llmContextOptimization,
    String? audioLanguage,
    String? captionLanguage,
    @Default(12) int whisperMaxAudioDuration,
    @Default(2) int inferenceInterval,
    @Default(256) int whisperDefaultMaxDecodeTokens,
    @Default(0.0) double whisperTemperature,
    @Default(0.1) double llmTemperature,
    @Default(256) int llmMaxTokens,
    @Default("") String llmPromptPrefix,
  }) = _AppSettingsData;

  factory AppSettingsData.fromJson(Map<String, dynamic> json) => _$AppSettingsDataFromJson(json);
}

@riverpod
class AppSettings extends _$AppSettings {
  @override
  Future<AppSettingsData> build() async {
    final box = await Hive.openBox("settings");
    final String modelWorkingDir = box.get(
      "model_working_dir",
      defaultValue: "${(await getApplicationSupportDirectory()).absolute.path.replaceAll("\\", "/")}/whisper",
    );
    final String whisperModel = box.get("whisper_model", defaultValue: "base");
    final String llmProviderUrl = box.get(
      "llm_provider_url",
      defaultValue: "http://localhost:11434/v1/chat/completions",
    );
    final String llmProviderKey = box.get("llm_provider_key", defaultValue: "");
    final String llmProviderModel = box.get("llm_provider_model", defaultValue: "");
    final llmContextOptimization = box.get("llm_context_optimization", defaultValue: true);

    final String? audioLanguage = box.get("audio_language");
    final String? captionLanguage = box.get("caption_language");
    final bool tryWithCuda = box.get("try_with_cuda", defaultValue: true);
    final bool withVAD = box.get("with_vad", defaultValue: true);
    final double vadThreshold = box.get("vad_threshold", defaultValue: 0.1);

    // 推理设置项
    final int whisperMaxAudioDuration = box.get("whisper_max_audio_duration", defaultValue: 12);
    final int inferenceInterval = box.get("inference_interval_ms", defaultValue: 2000);
    final int whisperDefaultMaxDecodeTokens = box.get("whisper_default_max_decode_tokens", defaultValue: 256);
    final double whisperTemperature = box.get("whisper_temperature", defaultValue: 0.0);
    final double llmTemperature = box.get("llm_temperature", defaultValue: 0.1);
    final int llmMaxTokens = box.get("llm_max_tokens", defaultValue: 256);
    final String llmPromptPrefix = box.get("llm_prompt_prefix", defaultValue: "");

    return AppSettingsData(
      modelWorkingDir: modelWorkingDir,
      whisperModel: whisperModel,
      llmProviderUrl: llmProviderUrl,
      llmProviderKey: llmProviderKey,
      llmProviderModel: llmProviderModel,
      audioLanguage: audioLanguage,
      captionLanguage: captionLanguage,
      tryWithCuda: tryWithCuda,
      llmContextOptimization: llmContextOptimization,
      whisperMaxAudioDuration: whisperMaxAudioDuration,
      inferenceInterval: inferenceInterval,
      whisperDefaultMaxDecodeTokens: whisperDefaultMaxDecodeTokens,
      whisperTemperature: whisperTemperature,
      llmTemperature: llmTemperature,
      llmMaxTokens: llmMaxTokens,
      llmPromptPrefix: llmPromptPrefix,
      withVAD: withVAD,
      vadThreshold: vadThreshold,
    );
  }

  Future<bool> setSettings(AppSettingsData settings) async {
    state = AsyncData(settings);
    return await _saveState();
  }

  Future<bool> _saveState() async {
    debugPrint("Saving settings: ${state.value}");
    try {
      final box = await Hive.openBox("settings");
      await box.put("model_working_dir", state.value!.modelWorkingDir);
      await box.put("whisper_model", state.value!.whisperModel);
      await box.put("llm_provider_url", state.value!.llmProviderUrl);
      await box.put("llm_provider_key", state.value!.llmProviderKey);
      await box.put("llm_provider_model", state.value!.llmProviderModel);
      await box.put("audio_language", state.value!.audioLanguage);
      await box.put("caption_language", state.value!.captionLanguage);
      await box.put("try_with_cuda", state.value!.tryWithCuda);
      await box.put("with_vad", state.value!.withVAD);
      await box.put("llm_context_optimization", state.value!.llmContextOptimization);
      await box.put("whisper_max_audio_duration", state.value!.whisperMaxAudioDuration);
      await box.put("inference_interval_ms", state.value!.inferenceInterval);
      await box.put("whisper_default_max_decode_tokens", state.value!.whisperDefaultMaxDecodeTokens);
      await box.put("whisper_temperature", state.value!.whisperTemperature);
      await box.put("llm_temperature", state.value!.llmTemperature);
      await box.put("llm_max_tokens", state.value!.llmMaxTokens);
      await box.put("vad_threshold", state.value!.vadThreshold);
      await box.put("llm_prompt_prefix", state.value!.llmPromptPrefix);
      return true;
    } catch (e) {
      debugPrint("Error saving settings: $e");
      return false;
    }
  }
}

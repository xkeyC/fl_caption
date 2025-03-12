
import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'settings_provider.g.dart';

part 'settings_provider.freezed.dart';

@freezed
class AppSettingsData with _$AppSettingsData {
  factory AppSettingsData({
    required String modelWorkingDir,
    required String whisperModel,
    required String llmProviderUrl,
    required String llmProviderKey,
    required String llmProviderModel,
  }) = _AppSettingsData;

  factory AppSettingsData.fromJson(Map<String, dynamic> json) =>
      _$AppSettingsDataFromJson(json);
}

@riverpod
class AppSettings extends _$AppSettings {
  @override
  Future<AppSettingsData> build() async {
    final box = await Hive.openBox("settings");
    final String modelWorkingDir = box.get(
      "model_working_dir",
      defaultValue:
          "${(await getApplicationSupportDirectory()).absolute.path.replaceAll("\\", "/")}/whisper",
    );
    final String whisperModel = box.get(
      "whisper_model",
      defaultValue: "base",
    );
    final String llmProviderUrl = box.get(
      "llm_provider_url",
      defaultValue: "http://localhost:11434/v1/chat/completions",
    );
    final String llmProviderKey = box.get("llm_provider_key", defaultValue: "");
    final String llmProviderModel = box.get(
      "llm_provider_model",
      defaultValue: "",
    );
    return AppSettingsData(
      modelWorkingDir: modelWorkingDir,
      whisperModel: whisperModel,
      llmProviderUrl: llmProviderUrl,
      llmProviderKey: llmProviderKey,
      llmProviderModel: llmProviderModel,
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
      return true;
    } catch (e) {
      debugPrint("Error saving settings: $e");
      return false;
    }
  }
}
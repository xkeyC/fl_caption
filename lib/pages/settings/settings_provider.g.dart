// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings_provider.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_AppSettingsData _$AppSettingsDataFromJson(Map<String, dynamic> json) =>
    _AppSettingsData(
      modelWorkingDir: json['modelWorkingDir'] as String,
      whisperModel: json['whisperModel'] as String,
      tryWithCuda: json['tryWithCuda'] as bool,
      withVAD: json['withVAD'] as bool,
      vadThreshold: (json['vadThreshold'] as num).toDouble(),
      llmProviderUrl: json['llmProviderUrl'] as String,
      llmProviderKey: json['llmProviderKey'] as String,
      llmProviderModel: json['llmProviderModel'] as String,
      llmContextOptimization: json['llmContextOptimization'] as bool,
      audioLanguage: json['audioLanguage'] as String?,
      captionLanguage: json['captionLanguage'] as String?,
      whisperMaxAudioDuration:
          (json['whisperMaxAudioDuration'] as num?)?.toInt() ?? 12,
      inferenceInterval: (json['inferenceInterval'] as num?)?.toInt() ?? 2,
      whisperDefaultMaxDecodeTokens:
          (json['whisperDefaultMaxDecodeTokens'] as num?)?.toInt() ?? 256,
      whisperTemperature:
          (json['whisperTemperature'] as num?)?.toDouble() ?? 0.0,
      llmTemperature: (json['llmTemperature'] as num?)?.toDouble() ?? 0.1,
      llmMaxTokens: (json['llmMaxTokens'] as num?)?.toInt() ?? 256,
      llmPromptPrefix: json['llmPromptPrefix'] as String? ?? "",
    );

Map<String, dynamic> _$AppSettingsDataToJson(_AppSettingsData instance) =>
    <String, dynamic>{
      'modelWorkingDir': instance.modelWorkingDir,
      'whisperModel': instance.whisperModel,
      'tryWithCuda': instance.tryWithCuda,
      'withVAD': instance.withVAD,
      'vadThreshold': instance.vadThreshold,
      'llmProviderUrl': instance.llmProviderUrl,
      'llmProviderKey': instance.llmProviderKey,
      'llmProviderModel': instance.llmProviderModel,
      'llmContextOptimization': instance.llmContextOptimization,
      'audioLanguage': instance.audioLanguage,
      'captionLanguage': instance.captionLanguage,
      'whisperMaxAudioDuration': instance.whisperMaxAudioDuration,
      'inferenceInterval': instance.inferenceInterval,
      'whisperDefaultMaxDecodeTokens': instance.whisperDefaultMaxDecodeTokens,
      'whisperTemperature': instance.whisperTemperature,
      'llmTemperature': instance.llmTemperature,
      'llmMaxTokens': instance.llmMaxTokens,
      'llmPromptPrefix': instance.llmPromptPrefix,
    };

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

@ProviderFor(AppSettings)
const appSettingsProvider = AppSettingsProvider._();

final class AppSettingsProvider
    extends $AsyncNotifierProvider<AppSettings, AppSettingsData> {
  const AppSettingsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appSettingsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appSettingsHash();

  @$internal
  @override
  AppSettings create() => AppSettings();
}

String _$appSettingsHash() => r'96c81bc4989baa5817b3da872b81fef4dc1514b8';

abstract class _$AppSettings extends $AsyncNotifier<AppSettingsData> {
  FutureOr<AppSettingsData> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<AsyncValue<AppSettingsData>, AppSettingsData>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<AppSettingsData>, AppSettingsData>,
              AsyncValue<AppSettingsData>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package

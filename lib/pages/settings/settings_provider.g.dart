// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings_provider.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$AppSettingsDataImpl _$$AppSettingsDataImplFromJson(
  Map<String, dynamic> json,
) => _$AppSettingsDataImpl(
  modelWorkingDir: json['modelWorkingDir'] as String,
  whisperModel: json['whisperModel'] as String,
  tryWithCuda: json['tryWithCuda'] as bool,
  withVAD: json['withVAD'] as bool,
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
  whisperTemperature: (json['whisperTemperature'] as num?)?.toDouble() ?? 0.0,
  llmTemperature: (json['llmTemperature'] as num?)?.toDouble() ?? 0.1,
  llmMaxTokens: (json['llmMaxTokens'] as num?)?.toInt() ?? 256,
);

Map<String, dynamic> _$$AppSettingsDataImplToJson(
  _$AppSettingsDataImpl instance,
) => <String, dynamic>{
  'modelWorkingDir': instance.modelWorkingDir,
  'whisperModel': instance.whisperModel,
  'tryWithCuda': instance.tryWithCuda,
  'withVAD': instance.withVAD,
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
};

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$appSettingsHash() => r'a2fb16a4e29be5043dc7ebff00ea909b950570ad';

/// See also [AppSettings].
@ProviderFor(AppSettings)
final appSettingsProvider =
    AutoDisposeAsyncNotifierProvider<AppSettings, AppSettingsData>.internal(
      AppSettings.new,
      name: r'appSettingsProvider',
      debugGetCreateSourceHash:
          const bool.fromEnvironment('dart.vm.product')
              ? null
              : _$appSettingsHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$AppSettings = AutoDisposeAsyncNotifier<AppSettingsData>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package

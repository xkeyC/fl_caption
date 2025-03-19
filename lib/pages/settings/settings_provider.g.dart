// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings_provider.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$AppSettingsDataImpl _$$AppSettingsDataImplFromJson(
        Map<String, dynamic> json) =>
    _$AppSettingsDataImpl(
      modelWorkingDir: json['modelWorkingDir'] as String,
      whisperModel: json['whisperModel'] as String,
      tryWithCuda: json['tryWithCuda'] as bool,
      llmProviderUrl: json['llmProviderUrl'] as String,
      llmProviderKey: json['llmProviderKey'] as String,
      llmProviderModel: json['llmProviderModel'] as String,
      llmContextOptimization: json['llmContextOptimization'] as bool,
      audioLanguage: json['audioLanguage'] as String?,
      captionLanguage: json['captionLanguage'] as String?,
    );

Map<String, dynamic> _$$AppSettingsDataImplToJson(
        _$AppSettingsDataImpl instance) =>
    <String, dynamic>{
      'modelWorkingDir': instance.modelWorkingDir,
      'whisperModel': instance.whisperModel,
      'tryWithCuda': instance.tryWithCuda,
      'llmProviderUrl': instance.llmProviderUrl,
      'llmProviderKey': instance.llmProviderKey,
      'llmProviderModel': instance.llmProviderModel,
      'llmContextOptimization': instance.llmContextOptimization,
      'audioLanguage': instance.audioLanguage,
      'captionLanguage': instance.captionLanguage,
    };

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$appSettingsHash() => r'30ae0e6d5dacba828b2a6836c3f5fe55c034f56a';

/// See also [AppSettings].
@ProviderFor(AppSettings)
final appSettingsProvider =
    AutoDisposeAsyncNotifierProvider<AppSettings, AppSettingsData>.internal(
  AppSettings.new,
  name: r'appSettingsProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$appSettingsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$AppSettings = AutoDisposeAsyncNotifier<AppSettingsData>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package

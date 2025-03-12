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
      llmProviderUrl: json['llmProviderUrl'] as String,
      llmProviderKey: json['llmProviderKey'] as String,
      llmProviderModel: json['llmProviderModel'] as String,
    );

Map<String, dynamic> _$$AppSettingsDataImplToJson(
        _$AppSettingsDataImpl instance) =>
    <String, dynamic>{
      'modelWorkingDir': instance.modelWorkingDir,
      'whisperModel': instance.whisperModel,
      'llmProviderUrl': instance.llmProviderUrl,
      'llmProviderKey': instance.llmProviderKey,
      'llmProviderModel': instance.llmProviderModel,
    };

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$appSettingsHash() => r'b76895f1a641e3b3eed28f1ee0d851a0586b7d78';

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

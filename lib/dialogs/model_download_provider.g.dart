// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'model_download_provider.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ModelDownloadStateData _$ModelDownloadStateDataFromJson(
  Map<String, dynamic> json,
) => _ModelDownloadStateData(
  modelName: json['modelName'] as String,
  modelPath: json['modelPath'] as String,
  currentProgress: (json['currentProgress'] as num).toInt(),
  currentTotal: (json['currentTotal'] as num).toInt(),
  isReady: json['isReady'] as bool,
  currentDownloadFileIndex: json['currentDownloadFileIndex'] ?? 0,
  errorText: json['errorText'] as String?,
);

Map<String, dynamic> _$ModelDownloadStateDataToJson(
  _ModelDownloadStateData instance,
) => <String, dynamic>{
  'modelName': instance.modelName,
  'modelPath': instance.modelPath,
  'currentProgress': instance.currentProgress,
  'currentTotal': instance.currentTotal,
  'isReady': instance.isReady,
  'currentDownloadFileIndex': instance.currentDownloadFileIndex,
  'errorText': instance.errorText,
};

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

@ProviderFor(ModelDownloadState)
const modelDownloadStateProvider = ModelDownloadStateFamily._();

final class ModelDownloadStateProvider
    extends $NotifierProvider<ModelDownloadState, ModelDownloadStateData> {
  const ModelDownloadStateProvider._({
    required ModelDownloadStateFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'modelDownloadStateProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$modelDownloadStateHash();

  @override
  String toString() {
    return r'modelDownloadStateProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  ModelDownloadState create() => ModelDownloadState();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ModelDownloadStateData value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ModelDownloadStateData>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ModelDownloadStateProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$modelDownloadStateHash() =>
    r'677e169e6a0a1c8ff4df4204a8b457521a93b1d2';

final class ModelDownloadStateFamily extends $Family
    with
        $ClassFamilyOverride<
          ModelDownloadState,
          ModelDownloadStateData,
          ModelDownloadStateData,
          ModelDownloadStateData,
          (String, String)
        > {
  const ModelDownloadStateFamily._()
    : super(
        retry: null,
        name: r'modelDownloadStateProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ModelDownloadStateProvider call(String modelName, String savePath) =>
      ModelDownloadStateProvider._(argument: (modelName, savePath), from: this);

  @override
  String toString() => r'modelDownloadStateProvider';
}

abstract class _$ModelDownloadState extends $Notifier<ModelDownloadStateData> {
  late final _$args = ref.$arg as (String, String);
  String get modelName => _$args.$1;
  String get savePath => _$args.$2;

  ModelDownloadStateData build(String modelName, String savePath);
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build(_$args.$1, _$args.$2);
    final ref =
        this.ref as $Ref<ModelDownloadStateData, ModelDownloadStateData>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ModelDownloadStateData, ModelDownloadStateData>,
              ModelDownloadStateData,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package

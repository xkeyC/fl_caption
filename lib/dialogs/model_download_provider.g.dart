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
  progress: (json['progress'] as num).toDouble(),
  isReady: json['isReady'] as bool,
  errorText: json['errorText'] as String?,
);

Map<String, dynamic> _$ModelDownloadStateDataToJson(
  _ModelDownloadStateData instance,
) => <String, dynamic>{
  'modelName': instance.modelName,
  'modelPath': instance.modelPath,
  'progress': instance.progress,
  'isReady': instance.isReady,
  'errorText': instance.errorText,
};

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$modelDownloadStateHash() =>
    r'60b6cc9f9929d438669ac0b6aac4ec8977cf6d51';

/// Copied from Dart SDK
class _SystemHash {
  _SystemHash._();

  static int combine(int hash, int value) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + value);
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    // ignore: parameter_assignments
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

abstract class _$ModelDownloadState
    extends BuildlessAutoDisposeNotifier<ModelDownloadStateData> {
  late final String modelName;
  late final String savePath;

  ModelDownloadStateData build(String modelName, String savePath);
}

/// See also [ModelDownloadState].
@ProviderFor(ModelDownloadState)
const modelDownloadStateProvider = ModelDownloadStateFamily();

/// See also [ModelDownloadState].
class ModelDownloadStateFamily extends Family<ModelDownloadStateData> {
  /// See also [ModelDownloadState].
  const ModelDownloadStateFamily();

  /// See also [ModelDownloadState].
  ModelDownloadStateProvider call(String modelName, String savePath) {
    return ModelDownloadStateProvider(modelName, savePath);
  }

  @override
  ModelDownloadStateProvider getProviderOverride(
    covariant ModelDownloadStateProvider provider,
  ) {
    return call(provider.modelName, provider.savePath);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'modelDownloadStateProvider';
}

/// See also [ModelDownloadState].
class ModelDownloadStateProvider
    extends
        AutoDisposeNotifierProviderImpl<
          ModelDownloadState,
          ModelDownloadStateData
        > {
  /// See also [ModelDownloadState].
  ModelDownloadStateProvider(String modelName, String savePath)
    : this._internal(
        () =>
            ModelDownloadState()
              ..modelName = modelName
              ..savePath = savePath,
        from: modelDownloadStateProvider,
        name: r'modelDownloadStateProvider',
        debugGetCreateSourceHash:
            const bool.fromEnvironment('dart.vm.product')
                ? null
                : _$modelDownloadStateHash,
        dependencies: ModelDownloadStateFamily._dependencies,
        allTransitiveDependencies:
            ModelDownloadStateFamily._allTransitiveDependencies,
        modelName: modelName,
        savePath: savePath,
      );

  ModelDownloadStateProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.modelName,
    required this.savePath,
  }) : super.internal();

  final String modelName;
  final String savePath;

  @override
  ModelDownloadStateData runNotifierBuild(
    covariant ModelDownloadState notifier,
  ) {
    return notifier.build(modelName, savePath);
  }

  @override
  Override overrideWith(ModelDownloadState Function() create) {
    return ProviderOverride(
      origin: this,
      override: ModelDownloadStateProvider._internal(
        () =>
            create()
              ..modelName = modelName
              ..savePath = savePath,
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        modelName: modelName,
        savePath: savePath,
      ),
    );
  }

  @override
  AutoDisposeNotifierProviderElement<ModelDownloadState, ModelDownloadStateData>
  createElement() {
    return _ModelDownloadStateProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is ModelDownloadStateProvider &&
        other.modelName == modelName &&
        other.savePath == savePath;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, modelName.hashCode);
    hash = _SystemHash.combine(hash, savePath.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin ModelDownloadStateRef
    on AutoDisposeNotifierProviderRef<ModelDownloadStateData> {
  /// The parameter `modelName` of this provider.
  String get modelName;

  /// The parameter `savePath` of this provider.
  String get savePath;
}

class _ModelDownloadStateProviderElement
    extends
        AutoDisposeNotifierProviderElement<
          ModelDownloadState,
          ModelDownloadStateData
        >
    with ModelDownloadStateRef {
  _ModelDownloadStateProviderElement(super.provider);

  @override
  String get modelName => (origin as ModelDownloadStateProvider).modelName;
  @override
  String get savePath => (origin as ModelDownloadStateProvider).savePath;
}

// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package

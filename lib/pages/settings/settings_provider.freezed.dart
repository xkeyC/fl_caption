// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'settings_provider.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

AppSettingsData _$AppSettingsDataFromJson(Map<String, dynamic> json) {
  return _AppSettingsData.fromJson(json);
}

/// @nodoc
mixin _$AppSettingsData {
  String get modelWorkingDir => throw _privateConstructorUsedError;
  String get whisperModel => throw _privateConstructorUsedError;
  bool get tryWithCuda => throw _privateConstructorUsedError;
  bool get withVAD => throw _privateConstructorUsedError;
  double get vadThreshold => throw _privateConstructorUsedError;
  String get llmProviderUrl => throw _privateConstructorUsedError;
  String get llmProviderKey => throw _privateConstructorUsedError;
  String get llmProviderModel => throw _privateConstructorUsedError;
  bool get llmContextOptimization => throw _privateConstructorUsedError;
  String? get audioLanguage => throw _privateConstructorUsedError;
  String? get captionLanguage => throw _privateConstructorUsedError;
  int get whisperMaxAudioDuration => throw _privateConstructorUsedError;
  int get inferenceInterval => throw _privateConstructorUsedError;
  int get whisperDefaultMaxDecodeTokens => throw _privateConstructorUsedError;
  double get whisperTemperature => throw _privateConstructorUsedError;
  double get llmTemperature => throw _privateConstructorUsedError;
  int get llmMaxTokens => throw _privateConstructorUsedError;

  /// Serializes this AppSettingsData to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of AppSettingsData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $AppSettingsDataCopyWith<AppSettingsData> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $AppSettingsDataCopyWith<$Res> {
  factory $AppSettingsDataCopyWith(
    AppSettingsData value,
    $Res Function(AppSettingsData) then,
  ) = _$AppSettingsDataCopyWithImpl<$Res, AppSettingsData>;
  @useResult
  $Res call({
    String modelWorkingDir,
    String whisperModel,
    bool tryWithCuda,
    bool withVAD,
    double vadThreshold,
    String llmProviderUrl,
    String llmProviderKey,
    String llmProviderModel,
    bool llmContextOptimization,
    String? audioLanguage,
    String? captionLanguage,
    int whisperMaxAudioDuration,
    int inferenceInterval,
    int whisperDefaultMaxDecodeTokens,
    double whisperTemperature,
    double llmTemperature,
    int llmMaxTokens,
  });
}

/// @nodoc
class _$AppSettingsDataCopyWithImpl<$Res, $Val extends AppSettingsData>
    implements $AppSettingsDataCopyWith<$Res> {
  _$AppSettingsDataCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of AppSettingsData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? modelWorkingDir = null,
    Object? whisperModel = null,
    Object? tryWithCuda = null,
    Object? withVAD = null,
    Object? vadThreshold = null,
    Object? llmProviderUrl = null,
    Object? llmProviderKey = null,
    Object? llmProviderModel = null,
    Object? llmContextOptimization = null,
    Object? audioLanguage = freezed,
    Object? captionLanguage = freezed,
    Object? whisperMaxAudioDuration = null,
    Object? inferenceInterval = null,
    Object? whisperDefaultMaxDecodeTokens = null,
    Object? whisperTemperature = null,
    Object? llmTemperature = null,
    Object? llmMaxTokens = null,
  }) {
    return _then(
      _value.copyWith(
            modelWorkingDir:
                null == modelWorkingDir
                    ? _value.modelWorkingDir
                    : modelWorkingDir // ignore: cast_nullable_to_non_nullable
                        as String,
            whisperModel:
                null == whisperModel
                    ? _value.whisperModel
                    : whisperModel // ignore: cast_nullable_to_non_nullable
                        as String,
            tryWithCuda:
                null == tryWithCuda
                    ? _value.tryWithCuda
                    : tryWithCuda // ignore: cast_nullable_to_non_nullable
                        as bool,
            withVAD:
                null == withVAD
                    ? _value.withVAD
                    : withVAD // ignore: cast_nullable_to_non_nullable
                        as bool,
            vadThreshold:
                null == vadThreshold
                    ? _value.vadThreshold
                    : vadThreshold // ignore: cast_nullable_to_non_nullable
                        as double,
            llmProviderUrl:
                null == llmProviderUrl
                    ? _value.llmProviderUrl
                    : llmProviderUrl // ignore: cast_nullable_to_non_nullable
                        as String,
            llmProviderKey:
                null == llmProviderKey
                    ? _value.llmProviderKey
                    : llmProviderKey // ignore: cast_nullable_to_non_nullable
                        as String,
            llmProviderModel:
                null == llmProviderModel
                    ? _value.llmProviderModel
                    : llmProviderModel // ignore: cast_nullable_to_non_nullable
                        as String,
            llmContextOptimization:
                null == llmContextOptimization
                    ? _value.llmContextOptimization
                    : llmContextOptimization // ignore: cast_nullable_to_non_nullable
                        as bool,
            audioLanguage:
                freezed == audioLanguage
                    ? _value.audioLanguage
                    : audioLanguage // ignore: cast_nullable_to_non_nullable
                        as String?,
            captionLanguage:
                freezed == captionLanguage
                    ? _value.captionLanguage
                    : captionLanguage // ignore: cast_nullable_to_non_nullable
                        as String?,
            whisperMaxAudioDuration:
                null == whisperMaxAudioDuration
                    ? _value.whisperMaxAudioDuration
                    : whisperMaxAudioDuration // ignore: cast_nullable_to_non_nullable
                        as int,
            inferenceInterval:
                null == inferenceInterval
                    ? _value.inferenceInterval
                    : inferenceInterval // ignore: cast_nullable_to_non_nullable
                        as int,
            whisperDefaultMaxDecodeTokens:
                null == whisperDefaultMaxDecodeTokens
                    ? _value.whisperDefaultMaxDecodeTokens
                    : whisperDefaultMaxDecodeTokens // ignore: cast_nullable_to_non_nullable
                        as int,
            whisperTemperature:
                null == whisperTemperature
                    ? _value.whisperTemperature
                    : whisperTemperature // ignore: cast_nullable_to_non_nullable
                        as double,
            llmTemperature:
                null == llmTemperature
                    ? _value.llmTemperature
                    : llmTemperature // ignore: cast_nullable_to_non_nullable
                        as double,
            llmMaxTokens:
                null == llmMaxTokens
                    ? _value.llmMaxTokens
                    : llmMaxTokens // ignore: cast_nullable_to_non_nullable
                        as int,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$AppSettingsDataImplCopyWith<$Res>
    implements $AppSettingsDataCopyWith<$Res> {
  factory _$$AppSettingsDataImplCopyWith(
    _$AppSettingsDataImpl value,
    $Res Function(_$AppSettingsDataImpl) then,
  ) = __$$AppSettingsDataImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String modelWorkingDir,
    String whisperModel,
    bool tryWithCuda,
    bool withVAD,
    double vadThreshold,
    String llmProviderUrl,
    String llmProviderKey,
    String llmProviderModel,
    bool llmContextOptimization,
    String? audioLanguage,
    String? captionLanguage,
    int whisperMaxAudioDuration,
    int inferenceInterval,
    int whisperDefaultMaxDecodeTokens,
    double whisperTemperature,
    double llmTemperature,
    int llmMaxTokens,
  });
}

/// @nodoc
class __$$AppSettingsDataImplCopyWithImpl<$Res>
    extends _$AppSettingsDataCopyWithImpl<$Res, _$AppSettingsDataImpl>
    implements _$$AppSettingsDataImplCopyWith<$Res> {
  __$$AppSettingsDataImplCopyWithImpl(
    _$AppSettingsDataImpl _value,
    $Res Function(_$AppSettingsDataImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of AppSettingsData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? modelWorkingDir = null,
    Object? whisperModel = null,
    Object? tryWithCuda = null,
    Object? withVAD = null,
    Object? vadThreshold = null,
    Object? llmProviderUrl = null,
    Object? llmProviderKey = null,
    Object? llmProviderModel = null,
    Object? llmContextOptimization = null,
    Object? audioLanguage = freezed,
    Object? captionLanguage = freezed,
    Object? whisperMaxAudioDuration = null,
    Object? inferenceInterval = null,
    Object? whisperDefaultMaxDecodeTokens = null,
    Object? whisperTemperature = null,
    Object? llmTemperature = null,
    Object? llmMaxTokens = null,
  }) {
    return _then(
      _$AppSettingsDataImpl(
        modelWorkingDir:
            null == modelWorkingDir
                ? _value.modelWorkingDir
                : modelWorkingDir // ignore: cast_nullable_to_non_nullable
                    as String,
        whisperModel:
            null == whisperModel
                ? _value.whisperModel
                : whisperModel // ignore: cast_nullable_to_non_nullable
                    as String,
        tryWithCuda:
            null == tryWithCuda
                ? _value.tryWithCuda
                : tryWithCuda // ignore: cast_nullable_to_non_nullable
                    as bool,
        withVAD:
            null == withVAD
                ? _value.withVAD
                : withVAD // ignore: cast_nullable_to_non_nullable
                    as bool,
        vadThreshold:
            null == vadThreshold
                ? _value.vadThreshold
                : vadThreshold // ignore: cast_nullable_to_non_nullable
                    as double,
        llmProviderUrl:
            null == llmProviderUrl
                ? _value.llmProviderUrl
                : llmProviderUrl // ignore: cast_nullable_to_non_nullable
                    as String,
        llmProviderKey:
            null == llmProviderKey
                ? _value.llmProviderKey
                : llmProviderKey // ignore: cast_nullable_to_non_nullable
                    as String,
        llmProviderModel:
            null == llmProviderModel
                ? _value.llmProviderModel
                : llmProviderModel // ignore: cast_nullable_to_non_nullable
                    as String,
        llmContextOptimization:
            null == llmContextOptimization
                ? _value.llmContextOptimization
                : llmContextOptimization // ignore: cast_nullable_to_non_nullable
                    as bool,
        audioLanguage:
            freezed == audioLanguage
                ? _value.audioLanguage
                : audioLanguage // ignore: cast_nullable_to_non_nullable
                    as String?,
        captionLanguage:
            freezed == captionLanguage
                ? _value.captionLanguage
                : captionLanguage // ignore: cast_nullable_to_non_nullable
                    as String?,
        whisperMaxAudioDuration:
            null == whisperMaxAudioDuration
                ? _value.whisperMaxAudioDuration
                : whisperMaxAudioDuration // ignore: cast_nullable_to_non_nullable
                    as int,
        inferenceInterval:
            null == inferenceInterval
                ? _value.inferenceInterval
                : inferenceInterval // ignore: cast_nullable_to_non_nullable
                    as int,
        whisperDefaultMaxDecodeTokens:
            null == whisperDefaultMaxDecodeTokens
                ? _value.whisperDefaultMaxDecodeTokens
                : whisperDefaultMaxDecodeTokens // ignore: cast_nullable_to_non_nullable
                    as int,
        whisperTemperature:
            null == whisperTemperature
                ? _value.whisperTemperature
                : whisperTemperature // ignore: cast_nullable_to_non_nullable
                    as double,
        llmTemperature:
            null == llmTemperature
                ? _value.llmTemperature
                : llmTemperature // ignore: cast_nullable_to_non_nullable
                    as double,
        llmMaxTokens:
            null == llmMaxTokens
                ? _value.llmMaxTokens
                : llmMaxTokens // ignore: cast_nullable_to_non_nullable
                    as int,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$AppSettingsDataImpl
    with DiagnosticableTreeMixin
    implements _AppSettingsData {
  _$AppSettingsDataImpl({
    required this.modelWorkingDir,
    required this.whisperModel,
    required this.tryWithCuda,
    required this.withVAD,
    required this.vadThreshold,
    required this.llmProviderUrl,
    required this.llmProviderKey,
    required this.llmProviderModel,
    required this.llmContextOptimization,
    this.audioLanguage,
    this.captionLanguage,
    this.whisperMaxAudioDuration = 12,
    this.inferenceInterval = 2,
    this.whisperDefaultMaxDecodeTokens = 256,
    this.whisperTemperature = 0.0,
    this.llmTemperature = 0.1,
    this.llmMaxTokens = 256,
  });

  factory _$AppSettingsDataImpl.fromJson(Map<String, dynamic> json) =>
      _$$AppSettingsDataImplFromJson(json);

  @override
  final String modelWorkingDir;
  @override
  final String whisperModel;
  @override
  final bool tryWithCuda;
  @override
  final bool withVAD;
  @override
  final double vadThreshold;
  @override
  final String llmProviderUrl;
  @override
  final String llmProviderKey;
  @override
  final String llmProviderModel;
  @override
  final bool llmContextOptimization;
  @override
  final String? audioLanguage;
  @override
  final String? captionLanguage;
  @override
  @JsonKey()
  final int whisperMaxAudioDuration;
  @override
  @JsonKey()
  final int inferenceInterval;
  @override
  @JsonKey()
  final int whisperDefaultMaxDecodeTokens;
  @override
  @JsonKey()
  final double whisperTemperature;
  @override
  @JsonKey()
  final double llmTemperature;
  @override
  @JsonKey()
  final int llmMaxTokens;

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) {
    return 'AppSettingsData(modelWorkingDir: $modelWorkingDir, whisperModel: $whisperModel, tryWithCuda: $tryWithCuda, withVAD: $withVAD, vadThreshold: $vadThreshold, llmProviderUrl: $llmProviderUrl, llmProviderKey: $llmProviderKey, llmProviderModel: $llmProviderModel, llmContextOptimization: $llmContextOptimization, audioLanguage: $audioLanguage, captionLanguage: $captionLanguage, whisperMaxAudioDuration: $whisperMaxAudioDuration, inferenceInterval: $inferenceInterval, whisperDefaultMaxDecodeTokens: $whisperDefaultMaxDecodeTokens, whisperTemperature: $whisperTemperature, llmTemperature: $llmTemperature, llmMaxTokens: $llmMaxTokens)';
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty('type', 'AppSettingsData'))
      ..add(DiagnosticsProperty('modelWorkingDir', modelWorkingDir))
      ..add(DiagnosticsProperty('whisperModel', whisperModel))
      ..add(DiagnosticsProperty('tryWithCuda', tryWithCuda))
      ..add(DiagnosticsProperty('withVAD', withVAD))
      ..add(DiagnosticsProperty('vadThreshold', vadThreshold))
      ..add(DiagnosticsProperty('llmProviderUrl', llmProviderUrl))
      ..add(DiagnosticsProperty('llmProviderKey', llmProviderKey))
      ..add(DiagnosticsProperty('llmProviderModel', llmProviderModel))
      ..add(
        DiagnosticsProperty('llmContextOptimization', llmContextOptimization),
      )
      ..add(DiagnosticsProperty('audioLanguage', audioLanguage))
      ..add(DiagnosticsProperty('captionLanguage', captionLanguage))
      ..add(
        DiagnosticsProperty('whisperMaxAudioDuration', whisperMaxAudioDuration),
      )
      ..add(DiagnosticsProperty('inferenceInterval', inferenceInterval))
      ..add(
        DiagnosticsProperty(
          'whisperDefaultMaxDecodeTokens',
          whisperDefaultMaxDecodeTokens,
        ),
      )
      ..add(DiagnosticsProperty('whisperTemperature', whisperTemperature))
      ..add(DiagnosticsProperty('llmTemperature', llmTemperature))
      ..add(DiagnosticsProperty('llmMaxTokens', llmMaxTokens));
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$AppSettingsDataImpl &&
            (identical(other.modelWorkingDir, modelWorkingDir) ||
                other.modelWorkingDir == modelWorkingDir) &&
            (identical(other.whisperModel, whisperModel) ||
                other.whisperModel == whisperModel) &&
            (identical(other.tryWithCuda, tryWithCuda) ||
                other.tryWithCuda == tryWithCuda) &&
            (identical(other.withVAD, withVAD) || other.withVAD == withVAD) &&
            (identical(other.vadThreshold, vadThreshold) ||
                other.vadThreshold == vadThreshold) &&
            (identical(other.llmProviderUrl, llmProviderUrl) ||
                other.llmProviderUrl == llmProviderUrl) &&
            (identical(other.llmProviderKey, llmProviderKey) ||
                other.llmProviderKey == llmProviderKey) &&
            (identical(other.llmProviderModel, llmProviderModel) ||
                other.llmProviderModel == llmProviderModel) &&
            (identical(other.llmContextOptimization, llmContextOptimization) ||
                other.llmContextOptimization == llmContextOptimization) &&
            (identical(other.audioLanguage, audioLanguage) ||
                other.audioLanguage == audioLanguage) &&
            (identical(other.captionLanguage, captionLanguage) ||
                other.captionLanguage == captionLanguage) &&
            (identical(
                  other.whisperMaxAudioDuration,
                  whisperMaxAudioDuration,
                ) ||
                other.whisperMaxAudioDuration == whisperMaxAudioDuration) &&
            (identical(other.inferenceInterval, inferenceInterval) ||
                other.inferenceInterval == inferenceInterval) &&
            (identical(
                  other.whisperDefaultMaxDecodeTokens,
                  whisperDefaultMaxDecodeTokens,
                ) ||
                other.whisperDefaultMaxDecodeTokens ==
                    whisperDefaultMaxDecodeTokens) &&
            (identical(other.whisperTemperature, whisperTemperature) ||
                other.whisperTemperature == whisperTemperature) &&
            (identical(other.llmTemperature, llmTemperature) ||
                other.llmTemperature == llmTemperature) &&
            (identical(other.llmMaxTokens, llmMaxTokens) ||
                other.llmMaxTokens == llmMaxTokens));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    modelWorkingDir,
    whisperModel,
    tryWithCuda,
    withVAD,
    vadThreshold,
    llmProviderUrl,
    llmProviderKey,
    llmProviderModel,
    llmContextOptimization,
    audioLanguage,
    captionLanguage,
    whisperMaxAudioDuration,
    inferenceInterval,
    whisperDefaultMaxDecodeTokens,
    whisperTemperature,
    llmTemperature,
    llmMaxTokens,
  );

  /// Create a copy of AppSettingsData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$AppSettingsDataImplCopyWith<_$AppSettingsDataImpl> get copyWith =>
      __$$AppSettingsDataImplCopyWithImpl<_$AppSettingsDataImpl>(
        this,
        _$identity,
      );

  @override
  Map<String, dynamic> toJson() {
    return _$$AppSettingsDataImplToJson(this);
  }
}

abstract class _AppSettingsData implements AppSettingsData {
  factory _AppSettingsData({
    required final String modelWorkingDir,
    required final String whisperModel,
    required final bool tryWithCuda,
    required final bool withVAD,
    required final double vadThreshold,
    required final String llmProviderUrl,
    required final String llmProviderKey,
    required final String llmProviderModel,
    required final bool llmContextOptimization,
    final String? audioLanguage,
    final String? captionLanguage,
    final int whisperMaxAudioDuration,
    final int inferenceInterval,
    final int whisperDefaultMaxDecodeTokens,
    final double whisperTemperature,
    final double llmTemperature,
    final int llmMaxTokens,
  }) = _$AppSettingsDataImpl;

  factory _AppSettingsData.fromJson(Map<String, dynamic> json) =
      _$AppSettingsDataImpl.fromJson;

  @override
  String get modelWorkingDir;
  @override
  String get whisperModel;
  @override
  bool get tryWithCuda;
  @override
  bool get withVAD;
  @override
  double get vadThreshold;
  @override
  String get llmProviderUrl;
  @override
  String get llmProviderKey;
  @override
  String get llmProviderModel;
  @override
  bool get llmContextOptimization;
  @override
  String? get audioLanguage;
  @override
  String? get captionLanguage;
  @override
  int get whisperMaxAudioDuration;
  @override
  int get inferenceInterval;
  @override
  int get whisperDefaultMaxDecodeTokens;
  @override
  double get whisperTemperature;
  @override
  double get llmTemperature;
  @override
  int get llmMaxTokens;

  /// Create a copy of AppSettingsData
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$AppSettingsDataImplCopyWith<_$AppSettingsDataImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

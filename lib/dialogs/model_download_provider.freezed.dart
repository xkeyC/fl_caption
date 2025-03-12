// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'model_download_provider.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

ModelDownloadStateData _$ModelDownloadStateDataFromJson(
    Map<String, dynamic> json) {
  return _ModelDownloadStateData.fromJson(json);
}

/// @nodoc
mixin _$ModelDownloadStateData {
  String get modelName => throw _privateConstructorUsedError;
  String get modelPath => throw _privateConstructorUsedError;
  double get progress => throw _privateConstructorUsedError;
  bool get isReady => throw _privateConstructorUsedError;
  String? get errorText => throw _privateConstructorUsedError;

  /// Serializes this ModelDownloadStateData to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ModelDownloadStateData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ModelDownloadStateDataCopyWith<ModelDownloadStateData> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ModelDownloadStateDataCopyWith<$Res> {
  factory $ModelDownloadStateDataCopyWith(ModelDownloadStateData value,
          $Res Function(ModelDownloadStateData) then) =
      _$ModelDownloadStateDataCopyWithImpl<$Res, ModelDownloadStateData>;
  @useResult
  $Res call(
      {String modelName,
      String modelPath,
      double progress,
      bool isReady,
      String? errorText});
}

/// @nodoc
class _$ModelDownloadStateDataCopyWithImpl<$Res,
        $Val extends ModelDownloadStateData>
    implements $ModelDownloadStateDataCopyWith<$Res> {
  _$ModelDownloadStateDataCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ModelDownloadStateData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? modelName = null,
    Object? modelPath = null,
    Object? progress = null,
    Object? isReady = null,
    Object? errorText = freezed,
  }) {
    return _then(_value.copyWith(
      modelName: null == modelName
          ? _value.modelName
          : modelName // ignore: cast_nullable_to_non_nullable
              as String,
      modelPath: null == modelPath
          ? _value.modelPath
          : modelPath // ignore: cast_nullable_to_non_nullable
              as String,
      progress: null == progress
          ? _value.progress
          : progress // ignore: cast_nullable_to_non_nullable
              as double,
      isReady: null == isReady
          ? _value.isReady
          : isReady // ignore: cast_nullable_to_non_nullable
              as bool,
      errorText: freezed == errorText
          ? _value.errorText
          : errorText // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ModelDownloadStateDataImplCopyWith<$Res>
    implements $ModelDownloadStateDataCopyWith<$Res> {
  factory _$$ModelDownloadStateDataImplCopyWith(
          _$ModelDownloadStateDataImpl value,
          $Res Function(_$ModelDownloadStateDataImpl) then) =
      __$$ModelDownloadStateDataImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String modelName,
      String modelPath,
      double progress,
      bool isReady,
      String? errorText});
}

/// @nodoc
class __$$ModelDownloadStateDataImplCopyWithImpl<$Res>
    extends _$ModelDownloadStateDataCopyWithImpl<$Res,
        _$ModelDownloadStateDataImpl>
    implements _$$ModelDownloadStateDataImplCopyWith<$Res> {
  __$$ModelDownloadStateDataImplCopyWithImpl(
      _$ModelDownloadStateDataImpl _value,
      $Res Function(_$ModelDownloadStateDataImpl) _then)
      : super(_value, _then);

  /// Create a copy of ModelDownloadStateData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? modelName = null,
    Object? modelPath = null,
    Object? progress = null,
    Object? isReady = null,
    Object? errorText = freezed,
  }) {
    return _then(_$ModelDownloadStateDataImpl(
      modelName: null == modelName
          ? _value.modelName
          : modelName // ignore: cast_nullable_to_non_nullable
              as String,
      modelPath: null == modelPath
          ? _value.modelPath
          : modelPath // ignore: cast_nullable_to_non_nullable
              as String,
      progress: null == progress
          ? _value.progress
          : progress // ignore: cast_nullable_to_non_nullable
              as double,
      isReady: null == isReady
          ? _value.isReady
          : isReady // ignore: cast_nullable_to_non_nullable
              as bool,
      errorText: freezed == errorText
          ? _value.errorText
          : errorText // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ModelDownloadStateDataImpl
    with DiagnosticableTreeMixin
    implements _ModelDownloadStateData {
  _$ModelDownloadStateDataImpl(
      {required this.modelName,
      required this.modelPath,
      required this.progress,
      required this.isReady,
      this.errorText});

  factory _$ModelDownloadStateDataImpl.fromJson(Map<String, dynamic> json) =>
      _$$ModelDownloadStateDataImplFromJson(json);

  @override
  final String modelName;
  @override
  final String modelPath;
  @override
  final double progress;
  @override
  final bool isReady;
  @override
  final String? errorText;

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) {
    return 'ModelDownloadStateData(modelName: $modelName, modelPath: $modelPath, progress: $progress, isReady: $isReady, errorText: $errorText)';
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty('type', 'ModelDownloadStateData'))
      ..add(DiagnosticsProperty('modelName', modelName))
      ..add(DiagnosticsProperty('modelPath', modelPath))
      ..add(DiagnosticsProperty('progress', progress))
      ..add(DiagnosticsProperty('isReady', isReady))
      ..add(DiagnosticsProperty('errorText', errorText));
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ModelDownloadStateDataImpl &&
            (identical(other.modelName, modelName) ||
                other.modelName == modelName) &&
            (identical(other.modelPath, modelPath) ||
                other.modelPath == modelPath) &&
            (identical(other.progress, progress) ||
                other.progress == progress) &&
            (identical(other.isReady, isReady) || other.isReady == isReady) &&
            (identical(other.errorText, errorText) ||
                other.errorText == errorText));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType, modelName, modelPath, progress, isReady, errorText);

  /// Create a copy of ModelDownloadStateData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ModelDownloadStateDataImplCopyWith<_$ModelDownloadStateDataImpl>
      get copyWith => __$$ModelDownloadStateDataImplCopyWithImpl<
          _$ModelDownloadStateDataImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ModelDownloadStateDataImplToJson(
      this,
    );
  }
}

abstract class _ModelDownloadStateData implements ModelDownloadStateData {
  factory _ModelDownloadStateData(
      {required final String modelName,
      required final String modelPath,
      required final double progress,
      required final bool isReady,
      final String? errorText}) = _$ModelDownloadStateDataImpl;

  factory _ModelDownloadStateData.fromJson(Map<String, dynamic> json) =
      _$ModelDownloadStateDataImpl.fromJson;

  @override
  String get modelName;
  @override
  String get modelPath;
  @override
  double get progress;
  @override
  bool get isReady;
  @override
  String? get errorText;

  /// Create a copy of ModelDownloadStateData
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ModelDownloadStateDataImplCopyWith<_$ModelDownloadStateDataImpl>
      get copyWith => throw _privateConstructorUsedError;
}

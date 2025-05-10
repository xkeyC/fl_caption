// dart format width=80
// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'model_download_provider.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ModelDownloadStateData implements DiagnosticableTreeMixin {

 String get modelName; String get modelPath; double get progress; bool get isReady; String? get errorText;
/// Create a copy of ModelDownloadStateData
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelDownloadStateDataCopyWith<ModelDownloadStateData> get copyWith => _$ModelDownloadStateDataCopyWithImpl<ModelDownloadStateData>(this as ModelDownloadStateData, _$identity);

  /// Serializes this ModelDownloadStateData to a JSON map.
  Map<String, dynamic> toJson();

@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'ModelDownloadStateData'))
    ..add(DiagnosticsProperty('modelName', modelName))..add(DiagnosticsProperty('modelPath', modelPath))..add(DiagnosticsProperty('progress', progress))..add(DiagnosticsProperty('isReady', isReady))..add(DiagnosticsProperty('errorText', errorText));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelDownloadStateData&&(identical(other.modelName, modelName) || other.modelName == modelName)&&(identical(other.modelPath, modelPath) || other.modelPath == modelPath)&&(identical(other.progress, progress) || other.progress == progress)&&(identical(other.isReady, isReady) || other.isReady == isReady)&&(identical(other.errorText, errorText) || other.errorText == errorText));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,modelName,modelPath,progress,isReady,errorText);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'ModelDownloadStateData(modelName: $modelName, modelPath: $modelPath, progress: $progress, isReady: $isReady, errorText: $errorText)';
}


}

/// @nodoc
abstract mixin class $ModelDownloadStateDataCopyWith<$Res>  {
  factory $ModelDownloadStateDataCopyWith(ModelDownloadStateData value, $Res Function(ModelDownloadStateData) _then) = _$ModelDownloadStateDataCopyWithImpl;
@useResult
$Res call({
 String modelName, String modelPath, double progress, bool isReady, String? errorText
});




}
/// @nodoc
class _$ModelDownloadStateDataCopyWithImpl<$Res>
    implements $ModelDownloadStateDataCopyWith<$Res> {
  _$ModelDownloadStateDataCopyWithImpl(this._self, this._then);

  final ModelDownloadStateData _self;
  final $Res Function(ModelDownloadStateData) _then;

/// Create a copy of ModelDownloadStateData
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? modelName = null,Object? modelPath = null,Object? progress = null,Object? isReady = null,Object? errorText = freezed,}) {
  return _then(_self.copyWith(
modelName: null == modelName ? _self.modelName : modelName // ignore: cast_nullable_to_non_nullable
as String,modelPath: null == modelPath ? _self.modelPath : modelPath // ignore: cast_nullable_to_non_nullable
as String,progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as double,isReady: null == isReady ? _self.isReady : isReady // ignore: cast_nullable_to_non_nullable
as bool,errorText: freezed == errorText ? _self.errorText : errorText // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// @nodoc
@JsonSerializable()

class _ModelDownloadStateData with DiagnosticableTreeMixin implements ModelDownloadStateData {
   _ModelDownloadStateData({required this.modelName, required this.modelPath, required this.progress, required this.isReady, this.errorText});
  factory _ModelDownloadStateData.fromJson(Map<String, dynamic> json) => _$ModelDownloadStateDataFromJson(json);

@override final  String modelName;
@override final  String modelPath;
@override final  double progress;
@override final  bool isReady;
@override final  String? errorText;

/// Create a copy of ModelDownloadStateData
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelDownloadStateDataCopyWith<_ModelDownloadStateData> get copyWith => __$ModelDownloadStateDataCopyWithImpl<_ModelDownloadStateData>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ModelDownloadStateDataToJson(this, );
}
@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'ModelDownloadStateData'))
    ..add(DiagnosticsProperty('modelName', modelName))..add(DiagnosticsProperty('modelPath', modelPath))..add(DiagnosticsProperty('progress', progress))..add(DiagnosticsProperty('isReady', isReady))..add(DiagnosticsProperty('errorText', errorText));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelDownloadStateData&&(identical(other.modelName, modelName) || other.modelName == modelName)&&(identical(other.modelPath, modelPath) || other.modelPath == modelPath)&&(identical(other.progress, progress) || other.progress == progress)&&(identical(other.isReady, isReady) || other.isReady == isReady)&&(identical(other.errorText, errorText) || other.errorText == errorText));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,modelName,modelPath,progress,isReady,errorText);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'ModelDownloadStateData(modelName: $modelName, modelPath: $modelPath, progress: $progress, isReady: $isReady, errorText: $errorText)';
}


}

/// @nodoc
abstract mixin class _$ModelDownloadStateDataCopyWith<$Res> implements $ModelDownloadStateDataCopyWith<$Res> {
  factory _$ModelDownloadStateDataCopyWith(_ModelDownloadStateData value, $Res Function(_ModelDownloadStateData) _then) = __$ModelDownloadStateDataCopyWithImpl;
@override @useResult
$Res call({
 String modelName, String modelPath, double progress, bool isReady, String? errorText
});




}
/// @nodoc
class __$ModelDownloadStateDataCopyWithImpl<$Res>
    implements _$ModelDownloadStateDataCopyWith<$Res> {
  __$ModelDownloadStateDataCopyWithImpl(this._self, this._then);

  final _ModelDownloadStateData _self;
  final $Res Function(_ModelDownloadStateData) _then;

/// Create a copy of ModelDownloadStateData
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? modelName = null,Object? modelPath = null,Object? progress = null,Object? isReady = null,Object? errorText = freezed,}) {
  return _then(_ModelDownloadStateData(
modelName: null == modelName ? _self.modelName : modelName // ignore: cast_nullable_to_non_nullable
as String,modelPath: null == modelPath ? _self.modelPath : modelPath // ignore: cast_nullable_to_non_nullable
as String,progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as double,isReady: null == isReady ? _self.isReady : isReady // ignore: cast_nullable_to_non_nullable
as bool,errorText: freezed == errorText ? _self.errorText : errorText // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on

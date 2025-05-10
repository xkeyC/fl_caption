// dart format width=80
// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'settings_provider.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$AppSettingsData implements DiagnosticableTreeMixin {

 String get modelWorkingDir; String get whisperModel; bool get tryWithCuda; bool get withVAD; double get vadThreshold; String get llmProviderUrl; String get llmProviderKey; String get llmProviderModel; bool get llmContextOptimization; String? get audioLanguage; String? get captionLanguage; int get whisperMaxAudioDuration; int get inferenceInterval; int get whisperDefaultMaxDecodeTokens; double get whisperTemperature; double get llmTemperature; int get llmMaxTokens; String get llmPromptPrefix;
/// Create a copy of AppSettingsData
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppSettingsDataCopyWith<AppSettingsData> get copyWith => _$AppSettingsDataCopyWithImpl<AppSettingsData>(this as AppSettingsData, _$identity);

  /// Serializes this AppSettingsData to a JSON map.
  Map<String, dynamic> toJson();

@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'AppSettingsData'))
    ..add(DiagnosticsProperty('modelWorkingDir', modelWorkingDir))..add(DiagnosticsProperty('whisperModel', whisperModel))..add(DiagnosticsProperty('tryWithCuda', tryWithCuda))..add(DiagnosticsProperty('withVAD', withVAD))..add(DiagnosticsProperty('vadThreshold', vadThreshold))..add(DiagnosticsProperty('llmProviderUrl', llmProviderUrl))..add(DiagnosticsProperty('llmProviderKey', llmProviderKey))..add(DiagnosticsProperty('llmProviderModel', llmProviderModel))..add(DiagnosticsProperty('llmContextOptimization', llmContextOptimization))..add(DiagnosticsProperty('audioLanguage', audioLanguage))..add(DiagnosticsProperty('captionLanguage', captionLanguage))..add(DiagnosticsProperty('whisperMaxAudioDuration', whisperMaxAudioDuration))..add(DiagnosticsProperty('inferenceInterval', inferenceInterval))..add(DiagnosticsProperty('whisperDefaultMaxDecodeTokens', whisperDefaultMaxDecodeTokens))..add(DiagnosticsProperty('whisperTemperature', whisperTemperature))..add(DiagnosticsProperty('llmTemperature', llmTemperature))..add(DiagnosticsProperty('llmMaxTokens', llmMaxTokens))..add(DiagnosticsProperty('llmPromptPrefix', llmPromptPrefix));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppSettingsData&&(identical(other.modelWorkingDir, modelWorkingDir) || other.modelWorkingDir == modelWorkingDir)&&(identical(other.whisperModel, whisperModel) || other.whisperModel == whisperModel)&&(identical(other.tryWithCuda, tryWithCuda) || other.tryWithCuda == tryWithCuda)&&(identical(other.withVAD, withVAD) || other.withVAD == withVAD)&&(identical(other.vadThreshold, vadThreshold) || other.vadThreshold == vadThreshold)&&(identical(other.llmProviderUrl, llmProviderUrl) || other.llmProviderUrl == llmProviderUrl)&&(identical(other.llmProviderKey, llmProviderKey) || other.llmProviderKey == llmProviderKey)&&(identical(other.llmProviderModel, llmProviderModel) || other.llmProviderModel == llmProviderModel)&&(identical(other.llmContextOptimization, llmContextOptimization) || other.llmContextOptimization == llmContextOptimization)&&(identical(other.audioLanguage, audioLanguage) || other.audioLanguage == audioLanguage)&&(identical(other.captionLanguage, captionLanguage) || other.captionLanguage == captionLanguage)&&(identical(other.whisperMaxAudioDuration, whisperMaxAudioDuration) || other.whisperMaxAudioDuration == whisperMaxAudioDuration)&&(identical(other.inferenceInterval, inferenceInterval) || other.inferenceInterval == inferenceInterval)&&(identical(other.whisperDefaultMaxDecodeTokens, whisperDefaultMaxDecodeTokens) || other.whisperDefaultMaxDecodeTokens == whisperDefaultMaxDecodeTokens)&&(identical(other.whisperTemperature, whisperTemperature) || other.whisperTemperature == whisperTemperature)&&(identical(other.llmTemperature, llmTemperature) || other.llmTemperature == llmTemperature)&&(identical(other.llmMaxTokens, llmMaxTokens) || other.llmMaxTokens == llmMaxTokens)&&(identical(other.llmPromptPrefix, llmPromptPrefix) || other.llmPromptPrefix == llmPromptPrefix));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,modelWorkingDir,whisperModel,tryWithCuda,withVAD,vadThreshold,llmProviderUrl,llmProviderKey,llmProviderModel,llmContextOptimization,audioLanguage,captionLanguage,whisperMaxAudioDuration,inferenceInterval,whisperDefaultMaxDecodeTokens,whisperTemperature,llmTemperature,llmMaxTokens,llmPromptPrefix);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'AppSettingsData(modelWorkingDir: $modelWorkingDir, whisperModel: $whisperModel, tryWithCuda: $tryWithCuda, withVAD: $withVAD, vadThreshold: $vadThreshold, llmProviderUrl: $llmProviderUrl, llmProviderKey: $llmProviderKey, llmProviderModel: $llmProviderModel, llmContextOptimization: $llmContextOptimization, audioLanguage: $audioLanguage, captionLanguage: $captionLanguage, whisperMaxAudioDuration: $whisperMaxAudioDuration, inferenceInterval: $inferenceInterval, whisperDefaultMaxDecodeTokens: $whisperDefaultMaxDecodeTokens, whisperTemperature: $whisperTemperature, llmTemperature: $llmTemperature, llmMaxTokens: $llmMaxTokens, llmPromptPrefix: $llmPromptPrefix)';
}


}

/// @nodoc
abstract mixin class $AppSettingsDataCopyWith<$Res>  {
  factory $AppSettingsDataCopyWith(AppSettingsData value, $Res Function(AppSettingsData) _then) = _$AppSettingsDataCopyWithImpl;
@useResult
$Res call({
 String modelWorkingDir, String whisperModel, bool tryWithCuda, bool withVAD, double vadThreshold, String llmProviderUrl, String llmProviderKey, String llmProviderModel, bool llmContextOptimization, String? audioLanguage, String? captionLanguage, int whisperMaxAudioDuration, int inferenceInterval, int whisperDefaultMaxDecodeTokens, double whisperTemperature, double llmTemperature, int llmMaxTokens, String llmPromptPrefix
});




}
/// @nodoc
class _$AppSettingsDataCopyWithImpl<$Res>
    implements $AppSettingsDataCopyWith<$Res> {
  _$AppSettingsDataCopyWithImpl(this._self, this._then);

  final AppSettingsData _self;
  final $Res Function(AppSettingsData) _then;

/// Create a copy of AppSettingsData
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? modelWorkingDir = null,Object? whisperModel = null,Object? tryWithCuda = null,Object? withVAD = null,Object? vadThreshold = null,Object? llmProviderUrl = null,Object? llmProviderKey = null,Object? llmProviderModel = null,Object? llmContextOptimization = null,Object? audioLanguage = freezed,Object? captionLanguage = freezed,Object? whisperMaxAudioDuration = null,Object? inferenceInterval = null,Object? whisperDefaultMaxDecodeTokens = null,Object? whisperTemperature = null,Object? llmTemperature = null,Object? llmMaxTokens = null,Object? llmPromptPrefix = null,}) {
  return _then(_self.copyWith(
modelWorkingDir: null == modelWorkingDir ? _self.modelWorkingDir : modelWorkingDir // ignore: cast_nullable_to_non_nullable
as String,whisperModel: null == whisperModel ? _self.whisperModel : whisperModel // ignore: cast_nullable_to_non_nullable
as String,tryWithCuda: null == tryWithCuda ? _self.tryWithCuda : tryWithCuda // ignore: cast_nullable_to_non_nullable
as bool,withVAD: null == withVAD ? _self.withVAD : withVAD // ignore: cast_nullable_to_non_nullable
as bool,vadThreshold: null == vadThreshold ? _self.vadThreshold : vadThreshold // ignore: cast_nullable_to_non_nullable
as double,llmProviderUrl: null == llmProviderUrl ? _self.llmProviderUrl : llmProviderUrl // ignore: cast_nullable_to_non_nullable
as String,llmProviderKey: null == llmProviderKey ? _self.llmProviderKey : llmProviderKey // ignore: cast_nullable_to_non_nullable
as String,llmProviderModel: null == llmProviderModel ? _self.llmProviderModel : llmProviderModel // ignore: cast_nullable_to_non_nullable
as String,llmContextOptimization: null == llmContextOptimization ? _self.llmContextOptimization : llmContextOptimization // ignore: cast_nullable_to_non_nullable
as bool,audioLanguage: freezed == audioLanguage ? _self.audioLanguage : audioLanguage // ignore: cast_nullable_to_non_nullable
as String?,captionLanguage: freezed == captionLanguage ? _self.captionLanguage : captionLanguage // ignore: cast_nullable_to_non_nullable
as String?,whisperMaxAudioDuration: null == whisperMaxAudioDuration ? _self.whisperMaxAudioDuration : whisperMaxAudioDuration // ignore: cast_nullable_to_non_nullable
as int,inferenceInterval: null == inferenceInterval ? _self.inferenceInterval : inferenceInterval // ignore: cast_nullable_to_non_nullable
as int,whisperDefaultMaxDecodeTokens: null == whisperDefaultMaxDecodeTokens ? _self.whisperDefaultMaxDecodeTokens : whisperDefaultMaxDecodeTokens // ignore: cast_nullable_to_non_nullable
as int,whisperTemperature: null == whisperTemperature ? _self.whisperTemperature : whisperTemperature // ignore: cast_nullable_to_non_nullable
as double,llmTemperature: null == llmTemperature ? _self.llmTemperature : llmTemperature // ignore: cast_nullable_to_non_nullable
as double,llmMaxTokens: null == llmMaxTokens ? _self.llmMaxTokens : llmMaxTokens // ignore: cast_nullable_to_non_nullable
as int,llmPromptPrefix: null == llmPromptPrefix ? _self.llmPromptPrefix : llmPromptPrefix // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// @nodoc
@JsonSerializable()

class _AppSettingsData with DiagnosticableTreeMixin implements AppSettingsData {
   _AppSettingsData({required this.modelWorkingDir, required this.whisperModel, required this.tryWithCuda, required this.withVAD, required this.vadThreshold, required this.llmProviderUrl, required this.llmProviderKey, required this.llmProviderModel, required this.llmContextOptimization, this.audioLanguage, this.captionLanguage, this.whisperMaxAudioDuration = 12, this.inferenceInterval = 2, this.whisperDefaultMaxDecodeTokens = 256, this.whisperTemperature = 0.0, this.llmTemperature = 0.1, this.llmMaxTokens = 256, this.llmPromptPrefix = ""});
  factory _AppSettingsData.fromJson(Map<String, dynamic> json) => _$AppSettingsDataFromJson(json);

@override final  String modelWorkingDir;
@override final  String whisperModel;
@override final  bool tryWithCuda;
@override final  bool withVAD;
@override final  double vadThreshold;
@override final  String llmProviderUrl;
@override final  String llmProviderKey;
@override final  String llmProviderModel;
@override final  bool llmContextOptimization;
@override final  String? audioLanguage;
@override final  String? captionLanguage;
@override@JsonKey() final  int whisperMaxAudioDuration;
@override@JsonKey() final  int inferenceInterval;
@override@JsonKey() final  int whisperDefaultMaxDecodeTokens;
@override@JsonKey() final  double whisperTemperature;
@override@JsonKey() final  double llmTemperature;
@override@JsonKey() final  int llmMaxTokens;
@override@JsonKey() final  String llmPromptPrefix;

/// Create a copy of AppSettingsData
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AppSettingsDataCopyWith<_AppSettingsData> get copyWith => __$AppSettingsDataCopyWithImpl<_AppSettingsData>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$AppSettingsDataToJson(this, );
}
@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'AppSettingsData'))
    ..add(DiagnosticsProperty('modelWorkingDir', modelWorkingDir))..add(DiagnosticsProperty('whisperModel', whisperModel))..add(DiagnosticsProperty('tryWithCuda', tryWithCuda))..add(DiagnosticsProperty('withVAD', withVAD))..add(DiagnosticsProperty('vadThreshold', vadThreshold))..add(DiagnosticsProperty('llmProviderUrl', llmProviderUrl))..add(DiagnosticsProperty('llmProviderKey', llmProviderKey))..add(DiagnosticsProperty('llmProviderModel', llmProviderModel))..add(DiagnosticsProperty('llmContextOptimization', llmContextOptimization))..add(DiagnosticsProperty('audioLanguage', audioLanguage))..add(DiagnosticsProperty('captionLanguage', captionLanguage))..add(DiagnosticsProperty('whisperMaxAudioDuration', whisperMaxAudioDuration))..add(DiagnosticsProperty('inferenceInterval', inferenceInterval))..add(DiagnosticsProperty('whisperDefaultMaxDecodeTokens', whisperDefaultMaxDecodeTokens))..add(DiagnosticsProperty('whisperTemperature', whisperTemperature))..add(DiagnosticsProperty('llmTemperature', llmTemperature))..add(DiagnosticsProperty('llmMaxTokens', llmMaxTokens))..add(DiagnosticsProperty('llmPromptPrefix', llmPromptPrefix));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AppSettingsData&&(identical(other.modelWorkingDir, modelWorkingDir) || other.modelWorkingDir == modelWorkingDir)&&(identical(other.whisperModel, whisperModel) || other.whisperModel == whisperModel)&&(identical(other.tryWithCuda, tryWithCuda) || other.tryWithCuda == tryWithCuda)&&(identical(other.withVAD, withVAD) || other.withVAD == withVAD)&&(identical(other.vadThreshold, vadThreshold) || other.vadThreshold == vadThreshold)&&(identical(other.llmProviderUrl, llmProviderUrl) || other.llmProviderUrl == llmProviderUrl)&&(identical(other.llmProviderKey, llmProviderKey) || other.llmProviderKey == llmProviderKey)&&(identical(other.llmProviderModel, llmProviderModel) || other.llmProviderModel == llmProviderModel)&&(identical(other.llmContextOptimization, llmContextOptimization) || other.llmContextOptimization == llmContextOptimization)&&(identical(other.audioLanguage, audioLanguage) || other.audioLanguage == audioLanguage)&&(identical(other.captionLanguage, captionLanguage) || other.captionLanguage == captionLanguage)&&(identical(other.whisperMaxAudioDuration, whisperMaxAudioDuration) || other.whisperMaxAudioDuration == whisperMaxAudioDuration)&&(identical(other.inferenceInterval, inferenceInterval) || other.inferenceInterval == inferenceInterval)&&(identical(other.whisperDefaultMaxDecodeTokens, whisperDefaultMaxDecodeTokens) || other.whisperDefaultMaxDecodeTokens == whisperDefaultMaxDecodeTokens)&&(identical(other.whisperTemperature, whisperTemperature) || other.whisperTemperature == whisperTemperature)&&(identical(other.llmTemperature, llmTemperature) || other.llmTemperature == llmTemperature)&&(identical(other.llmMaxTokens, llmMaxTokens) || other.llmMaxTokens == llmMaxTokens)&&(identical(other.llmPromptPrefix, llmPromptPrefix) || other.llmPromptPrefix == llmPromptPrefix));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,modelWorkingDir,whisperModel,tryWithCuda,withVAD,vadThreshold,llmProviderUrl,llmProviderKey,llmProviderModel,llmContextOptimization,audioLanguage,captionLanguage,whisperMaxAudioDuration,inferenceInterval,whisperDefaultMaxDecodeTokens,whisperTemperature,llmTemperature,llmMaxTokens,llmPromptPrefix);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'AppSettingsData(modelWorkingDir: $modelWorkingDir, whisperModel: $whisperModel, tryWithCuda: $tryWithCuda, withVAD: $withVAD, vadThreshold: $vadThreshold, llmProviderUrl: $llmProviderUrl, llmProviderKey: $llmProviderKey, llmProviderModel: $llmProviderModel, llmContextOptimization: $llmContextOptimization, audioLanguage: $audioLanguage, captionLanguage: $captionLanguage, whisperMaxAudioDuration: $whisperMaxAudioDuration, inferenceInterval: $inferenceInterval, whisperDefaultMaxDecodeTokens: $whisperDefaultMaxDecodeTokens, whisperTemperature: $whisperTemperature, llmTemperature: $llmTemperature, llmMaxTokens: $llmMaxTokens, llmPromptPrefix: $llmPromptPrefix)';
}


}

/// @nodoc
abstract mixin class _$AppSettingsDataCopyWith<$Res> implements $AppSettingsDataCopyWith<$Res> {
  factory _$AppSettingsDataCopyWith(_AppSettingsData value, $Res Function(_AppSettingsData) _then) = __$AppSettingsDataCopyWithImpl;
@override @useResult
$Res call({
 String modelWorkingDir, String whisperModel, bool tryWithCuda, bool withVAD, double vadThreshold, String llmProviderUrl, String llmProviderKey, String llmProviderModel, bool llmContextOptimization, String? audioLanguage, String? captionLanguage, int whisperMaxAudioDuration, int inferenceInterval, int whisperDefaultMaxDecodeTokens, double whisperTemperature, double llmTemperature, int llmMaxTokens, String llmPromptPrefix
});




}
/// @nodoc
class __$AppSettingsDataCopyWithImpl<$Res>
    implements _$AppSettingsDataCopyWith<$Res> {
  __$AppSettingsDataCopyWithImpl(this._self, this._then);

  final _AppSettingsData _self;
  final $Res Function(_AppSettingsData) _then;

/// Create a copy of AppSettingsData
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? modelWorkingDir = null,Object? whisperModel = null,Object? tryWithCuda = null,Object? withVAD = null,Object? vadThreshold = null,Object? llmProviderUrl = null,Object? llmProviderKey = null,Object? llmProviderModel = null,Object? llmContextOptimization = null,Object? audioLanguage = freezed,Object? captionLanguage = freezed,Object? whisperMaxAudioDuration = null,Object? inferenceInterval = null,Object? whisperDefaultMaxDecodeTokens = null,Object? whisperTemperature = null,Object? llmTemperature = null,Object? llmMaxTokens = null,Object? llmPromptPrefix = null,}) {
  return _then(_AppSettingsData(
modelWorkingDir: null == modelWorkingDir ? _self.modelWorkingDir : modelWorkingDir // ignore: cast_nullable_to_non_nullable
as String,whisperModel: null == whisperModel ? _self.whisperModel : whisperModel // ignore: cast_nullable_to_non_nullable
as String,tryWithCuda: null == tryWithCuda ? _self.tryWithCuda : tryWithCuda // ignore: cast_nullable_to_non_nullable
as bool,withVAD: null == withVAD ? _self.withVAD : withVAD // ignore: cast_nullable_to_non_nullable
as bool,vadThreshold: null == vadThreshold ? _self.vadThreshold : vadThreshold // ignore: cast_nullable_to_non_nullable
as double,llmProviderUrl: null == llmProviderUrl ? _self.llmProviderUrl : llmProviderUrl // ignore: cast_nullable_to_non_nullable
as String,llmProviderKey: null == llmProviderKey ? _self.llmProviderKey : llmProviderKey // ignore: cast_nullable_to_non_nullable
as String,llmProviderModel: null == llmProviderModel ? _self.llmProviderModel : llmProviderModel // ignore: cast_nullable_to_non_nullable
as String,llmContextOptimization: null == llmContextOptimization ? _self.llmContextOptimization : llmContextOptimization // ignore: cast_nullable_to_non_nullable
as bool,audioLanguage: freezed == audioLanguage ? _self.audioLanguage : audioLanguage // ignore: cast_nullable_to_non_nullable
as String?,captionLanguage: freezed == captionLanguage ? _self.captionLanguage : captionLanguage // ignore: cast_nullable_to_non_nullable
as String?,whisperMaxAudioDuration: null == whisperMaxAudioDuration ? _self.whisperMaxAudioDuration : whisperMaxAudioDuration // ignore: cast_nullable_to_non_nullable
as int,inferenceInterval: null == inferenceInterval ? _self.inferenceInterval : inferenceInterval // ignore: cast_nullable_to_non_nullable
as int,whisperDefaultMaxDecodeTokens: null == whisperDefaultMaxDecodeTokens ? _self.whisperDefaultMaxDecodeTokens : whisperDefaultMaxDecodeTokens // ignore: cast_nullable_to_non_nullable
as int,whisperTemperature: null == whisperTemperature ? _self.whisperTemperature : whisperTemperature // ignore: cast_nullable_to_non_nullable
as double,llmTemperature: null == llmTemperature ? _self.llmTemperature : llmTemperature // ignore: cast_nullable_to_non_nullable
as double,llmMaxTokens: null == llmMaxTokens ? _self.llmMaxTokens : llmMaxTokens // ignore: cast_nullable_to_non_nullable
as int,llmPromptPrefix: null == llmPromptPrefix ? _self.llmPromptPrefix : llmPromptPrefix // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on

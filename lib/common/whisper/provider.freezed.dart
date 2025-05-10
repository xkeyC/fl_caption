// dart format width=80
// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'provider.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$DartWhisperClient implements DiagnosticableTreeMixin {

 rs.WhisperClient get client; DartWhisperClientError? get errorType;
/// Create a copy of DartWhisperClient
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DartWhisperClientCopyWith<DartWhisperClient> get copyWith => _$DartWhisperClientCopyWithImpl<DartWhisperClient>(this as DartWhisperClient, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'DartWhisperClient'))
    ..add(DiagnosticsProperty('client', client))..add(DiagnosticsProperty('errorType', errorType));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DartWhisperClient&&(identical(other.client, client) || other.client == client)&&(identical(other.errorType, errorType) || other.errorType == errorType));
}


@override
int get hashCode => Object.hash(runtimeType,client,errorType);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'DartWhisperClient(client: $client, errorType: $errorType)';
}


}

/// @nodoc
abstract mixin class $DartWhisperClientCopyWith<$Res>  {
  factory $DartWhisperClientCopyWith(DartWhisperClient value, $Res Function(DartWhisperClient) _then) = _$DartWhisperClientCopyWithImpl;
@useResult
$Res call({
 rs.WhisperClient client, DartWhisperClientError? errorType
});




}
/// @nodoc
class _$DartWhisperClientCopyWithImpl<$Res>
    implements $DartWhisperClientCopyWith<$Res> {
  _$DartWhisperClientCopyWithImpl(this._self, this._then);

  final DartWhisperClient _self;
  final $Res Function(DartWhisperClient) _then;

/// Create a copy of DartWhisperClient
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? client = null,Object? errorType = freezed,}) {
  return _then(_self.copyWith(
client: null == client ? _self.client : client // ignore: cast_nullable_to_non_nullable
as rs.WhisperClient,errorType: freezed == errorType ? _self.errorType : errorType // ignore: cast_nullable_to_non_nullable
as DartWhisperClientError?,
  ));
}

}


/// @nodoc


class _DartWhisperClient with DiagnosticableTreeMixin implements DartWhisperClient {
   _DartWhisperClient({required this.client, this.errorType});
  

@override final  rs.WhisperClient client;
@override final  DartWhisperClientError? errorType;

/// Create a copy of DartWhisperClient
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DartWhisperClientCopyWith<_DartWhisperClient> get copyWith => __$DartWhisperClientCopyWithImpl<_DartWhisperClient>(this, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'DartWhisperClient'))
    ..add(DiagnosticsProperty('client', client))..add(DiagnosticsProperty('errorType', errorType));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _DartWhisperClient&&(identical(other.client, client) || other.client == client)&&(identical(other.errorType, errorType) || other.errorType == errorType));
}


@override
int get hashCode => Object.hash(runtimeType,client,errorType);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'DartWhisperClient(client: $client, errorType: $errorType)';
}


}

/// @nodoc
abstract mixin class _$DartWhisperClientCopyWith<$Res> implements $DartWhisperClientCopyWith<$Res> {
  factory _$DartWhisperClientCopyWith(_DartWhisperClient value, $Res Function(_DartWhisperClient) _then) = __$DartWhisperClientCopyWithImpl;
@override @useResult
$Res call({
 rs.WhisperClient client, DartWhisperClientError? errorType
});




}
/// @nodoc
class __$DartWhisperClientCopyWithImpl<$Res>
    implements _$DartWhisperClientCopyWith<$Res> {
  __$DartWhisperClientCopyWithImpl(this._self, this._then);

  final _DartWhisperClient _self;
  final $Res Function(_DartWhisperClient) _then;

/// Create a copy of DartWhisperClient
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? client = null,Object? errorType = freezed,}) {
  return _then(_DartWhisperClient(
client: null == client ? _self.client : client // ignore: cast_nullable_to_non_nullable
as rs.WhisperClient,errorType: freezed == errorType ? _self.errorType : errorType // ignore: cast_nullable_to_non_nullable
as DartWhisperClientError?,
  ));
}


}

// dart format on

// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'provider.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$DartWhisperClient {
  rs.WhisperClient get client => throw _privateConstructorUsedError;
  DartWhisperClientError? get errorType => throw _privateConstructorUsedError;

  /// Create a copy of DartWhisperClient
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $DartWhisperClientCopyWith<DartWhisperClient> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $DartWhisperClientCopyWith<$Res> {
  factory $DartWhisperClientCopyWith(
    DartWhisperClient value,
    $Res Function(DartWhisperClient) then,
  ) = _$DartWhisperClientCopyWithImpl<$Res, DartWhisperClient>;
  @useResult
  $Res call({rs.WhisperClient client, DartWhisperClientError? errorType});
}

/// @nodoc
class _$DartWhisperClientCopyWithImpl<$Res, $Val extends DartWhisperClient>
    implements $DartWhisperClientCopyWith<$Res> {
  _$DartWhisperClientCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of DartWhisperClient
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? client = null, Object? errorType = freezed}) {
    return _then(
      _value.copyWith(
            client:
                null == client
                    ? _value.client
                    : client // ignore: cast_nullable_to_non_nullable
                        as rs.WhisperClient,
            errorType:
                freezed == errorType
                    ? _value.errorType
                    : errorType // ignore: cast_nullable_to_non_nullable
                        as DartWhisperClientError?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$DartWhisperClientImplCopyWith<$Res>
    implements $DartWhisperClientCopyWith<$Res> {
  factory _$$DartWhisperClientImplCopyWith(
    _$DartWhisperClientImpl value,
    $Res Function(_$DartWhisperClientImpl) then,
  ) = __$$DartWhisperClientImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({rs.WhisperClient client, DartWhisperClientError? errorType});
}

/// @nodoc
class __$$DartWhisperClientImplCopyWithImpl<$Res>
    extends _$DartWhisperClientCopyWithImpl<$Res, _$DartWhisperClientImpl>
    implements _$$DartWhisperClientImplCopyWith<$Res> {
  __$$DartWhisperClientImplCopyWithImpl(
    _$DartWhisperClientImpl _value,
    $Res Function(_$DartWhisperClientImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of DartWhisperClient
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? client = null, Object? errorType = freezed}) {
    return _then(
      _$DartWhisperClientImpl(
        client:
            null == client
                ? _value.client
                : client // ignore: cast_nullable_to_non_nullable
                    as rs.WhisperClient,
        errorType:
            freezed == errorType
                ? _value.errorType
                : errorType // ignore: cast_nullable_to_non_nullable
                    as DartWhisperClientError?,
      ),
    );
  }
}

/// @nodoc

class _$DartWhisperClientImpl
    with DiagnosticableTreeMixin
    implements _DartWhisperClient {
  _$DartWhisperClientImpl({required this.client, this.errorType});

  @override
  final rs.WhisperClient client;
  @override
  final DartWhisperClientError? errorType;

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) {
    return 'DartWhisperClient(client: $client, errorType: $errorType)';
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty('type', 'DartWhisperClient'))
      ..add(DiagnosticsProperty('client', client))
      ..add(DiagnosticsProperty('errorType', errorType));
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$DartWhisperClientImpl &&
            (identical(other.client, client) || other.client == client) &&
            (identical(other.errorType, errorType) ||
                other.errorType == errorType));
  }

  @override
  int get hashCode => Object.hash(runtimeType, client, errorType);

  /// Create a copy of DartWhisperClient
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$DartWhisperClientImplCopyWith<_$DartWhisperClientImpl> get copyWith =>
      __$$DartWhisperClientImplCopyWithImpl<_$DartWhisperClientImpl>(
        this,
        _$identity,
      );
}

abstract class _DartWhisperClient implements DartWhisperClient {
  factory _DartWhisperClient({
    required final rs.WhisperClient client,
    final DartWhisperClientError? errorType,
  }) = _$DartWhisperClientImpl;

  @override
  rs.WhisperClient get client;
  @override
  DartWhisperClientError? get errorType;

  /// Create a copy of DartWhisperClient
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$DartWhisperClientImplCopyWith<_$DartWhisperClientImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

@ProviderFor(DartWhisper)
const dartWhisperProvider = DartWhisperProvider._();

final class DartWhisperProvider
    extends $AsyncNotifierProvider<DartWhisper, DartWhisperClient> {
  const DartWhisperProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'dartWhisperProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$dartWhisperHash();

  @$internal
  @override
  DartWhisper create() => DartWhisper();
}

String _$dartWhisperHash() => r'71a5a698555a386b24fe64f37e44f26517029d82';

abstract class _$DartWhisper extends $AsyncNotifier<DartWhisperClient> {
  FutureOr<DartWhisperClient> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref =
        this.ref as $Ref<AsyncValue<DartWhisperClient>, DartWhisperClient>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<DartWhisperClient>, DartWhisperClient>,
              AsyncValue<DartWhisperClient>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

@ProviderFor(DartWhisperCaption)
const dartWhisperCaptionProvider = DartWhisperCaptionProvider._();

final class DartWhisperCaptionProvider
    extends
        $AsyncNotifierProvider<DartWhisperCaption, DartWhisperCaptionResult> {
  const DartWhisperCaptionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'dartWhisperCaptionProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$dartWhisperCaptionHash();

  @$internal
  @override
  DartWhisperCaption create() => DartWhisperCaption();
}

String _$dartWhisperCaptionHash() =>
    r'64273be1e1c0428182ab91b580e52eaab596b607';

abstract class _$DartWhisperCaption
    extends $AsyncNotifier<DartWhisperCaptionResult> {
  FutureOr<DartWhisperCaptionResult> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref =
        this.ref
            as $Ref<
              AsyncValue<DartWhisperCaptionResult>,
              DartWhisperCaptionResult
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<DartWhisperCaptionResult>,
                DartWhisperCaptionResult
              >,
              AsyncValue<DartWhisperCaptionResult>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package

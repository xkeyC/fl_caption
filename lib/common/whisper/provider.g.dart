// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$dartWhisperHash() => r'dd6be82f90b9287037bc23d91dafef149abe05a0';

/// See also [DartWhisper].
@ProviderFor(DartWhisper)
final dartWhisperProvider =
    AutoDisposeAsyncNotifierProvider<DartWhisper, DartWhisperClient>.internal(
      DartWhisper.new,
      name: r'dartWhisperProvider',
      debugGetCreateSourceHash:
          const bool.fromEnvironment('dart.vm.product')
              ? null
              : _$dartWhisperHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$DartWhisper = AutoDisposeAsyncNotifier<DartWhisperClient>;
String _$dartWhisperCaptionHash() =>
    r'a983dd95ae43b002b8dfc74532ef46708c38fb1a';

/// See also [DartWhisperCaption].
@ProviderFor(DartWhisperCaption)
final dartWhisperCaptionProvider = AutoDisposeAsyncNotifierProvider<
  DartWhisperCaption,
  DartWhisperCaptionResult
>.internal(
  DartWhisperCaption.new,
  name: r'dartWhisperCaptionProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$dartWhisperCaptionHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$DartWhisperCaption =
    AutoDisposeAsyncNotifier<DartWhisperCaptionResult>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package

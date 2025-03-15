// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$dartWhisperHash() => r'fdf3e6d259247bde5020adc76346af199c9bdfb5';

/// See also [DartWhisper].
@ProviderFor(DartWhisper)
final dartWhisperProvider =
    AutoDisposeAsyncNotifierProvider<DartWhisper, DartWhisperClient>.internal(
  DartWhisper.new,
  name: r'dartWhisperProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$dartWhisperHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$DartWhisper = AutoDisposeAsyncNotifier<DartWhisperClient>;
String _$dartWhisperCaptionHash() =>
    r'452b4efc58da0cfd15390cdf0f708c3739b47e45';

/// See also [DartWhisperCaption].
@ProviderFor(DartWhisperCaption)
final dartWhisperCaptionProvider = AutoDisposeAsyncNotifierProvider<
    DartWhisperCaption, DartWhisperCaptionResult>.internal(
  DartWhisperCaption.new,
  name: r'dartWhisperCaptionProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$dartWhisperCaptionHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$DartWhisperCaption
    = AutoDisposeAsyncNotifier<DartWhisperCaptionResult>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package

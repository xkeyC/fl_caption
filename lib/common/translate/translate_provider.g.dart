// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'translate_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(TranslateProvider)
const translateProviderProvider = TranslateProviderProvider._();

final class TranslateProviderProvider
    extends $NotifierProvider<TranslateProvider, String> {
  const TranslateProviderProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'translateProviderProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$translateProviderHash();

  @$internal
  @override
  TranslateProvider create() => TranslateProvider();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }
}

String _$translateProviderHash() => r'23c0d3433216c8173e97b22ddfad2130b2089b37';

abstract class _$TranslateProvider extends $Notifier<String> {
  String build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<String, String>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String, String>,
              String,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

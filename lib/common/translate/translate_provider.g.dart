// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'translate_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

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

String _$translateProviderHash() => r'1826f87ec78dc1e30872a36007405407dd8beae7';

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

// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package

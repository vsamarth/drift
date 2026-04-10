// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'receive_feature.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(receiveFeatureVisuals)
final receiveFeatureVisualsProvider = ReceiveFeatureVisualsProvider._();

final class ReceiveFeatureVisualsProvider
    extends
        $FunctionalProvider<
          ReceiveFeatureVisuals,
          ReceiveFeatureVisuals,
          ReceiveFeatureVisuals
        >
    with $Provider<ReceiveFeatureVisuals> {
  ReceiveFeatureVisualsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'receiveFeatureVisualsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$receiveFeatureVisualsHash();

  @$internal
  @override
  $ProviderElement<ReceiveFeatureVisuals> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ReceiveFeatureVisuals create(Ref ref) {
    return receiveFeatureVisuals(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ReceiveFeatureVisuals value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ReceiveFeatureVisuals>(value),
    );
  }
}

String _$receiveFeatureVisualsHash() =>
    r'a3e99ca22115a868841633239df57d1c523dba41';

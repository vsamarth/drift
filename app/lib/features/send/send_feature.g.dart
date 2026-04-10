// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'send_feature.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(sendFeatureVisuals)
final sendFeatureVisualsProvider = SendFeatureVisualsProvider._();

final class SendFeatureVisualsProvider
    extends
        $FunctionalProvider<
          SendFeatureVisuals,
          SendFeatureVisuals,
          SendFeatureVisuals
        >
    with $Provider<SendFeatureVisuals> {
  SendFeatureVisualsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sendFeatureVisualsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sendFeatureVisualsHash();

  @$internal
  @override
  $ProviderElement<SendFeatureVisuals> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SendFeatureVisuals create(Ref ref) {
    return sendFeatureVisuals(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SendFeatureVisuals value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SendFeatureVisuals>(value),
    );
  }
}

String _$sendFeatureVisualsHash() =>
    r'4999bf8e82455e3d48dfed8fed5edf5143ec26be';

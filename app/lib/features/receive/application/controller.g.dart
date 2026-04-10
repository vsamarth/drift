// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(receiverIdleViewState)
final receiverIdleViewStateProvider = ReceiverIdleViewStateProvider._();

final class ReceiverIdleViewStateProvider
    extends
        $FunctionalProvider<
          ReceiverIdleViewState,
          ReceiverIdleViewState,
          ReceiverIdleViewState
        >
    with $Provider<ReceiverIdleViewState> {
  ReceiverIdleViewStateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'receiverIdleViewStateProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$receiverIdleViewStateHash();

  @$internal
  @override
  $ProviderElement<ReceiverIdleViewState> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ReceiverIdleViewState create(Ref ref) {
    return receiverIdleViewState(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ReceiverIdleViewState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ReceiverIdleViewState>(value),
    );
  }
}

String _$receiverIdleViewStateHash() =>
    r'9ee3bc7bbecbeca0b4985de3328686752c87749c';

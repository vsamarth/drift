import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../platform/rust/receiver/fake_source.dart';
import '../../../platform/rust/receiver/source.dart';
import 'state.dart';

final receiverServiceSourceProvider = Provider<ReceiverServiceSource>(
  (ref) => FakeReceiverServiceSource(),
);

final receiverServiceProvider = NotifierProvider<
  ReceiverServiceController,
  ReceiverServiceState
>(ReceiverServiceController.new);

class ReceiverServiceController extends Notifier<ReceiverServiceState> {
  StreamSubscription<ReceiverServiceState>? _subscription;

  @override
  ReceiverServiceState build() {
    final source = ref.watch(receiverServiceSourceProvider);
    _subscription?.cancel();
    _subscription = source.watchState().listen((next) {
      state = next;
    });
    ref.onDispose(() => _subscription?.cancel());
    return source.currentState;
  }

  Future<void> setup({String? serverUrl}) {
    return ref.read(receiverServiceSourceProvider).setup(serverUrl: serverUrl);
  }

  Future<void> ensureRegistered({String? serverUrl}) {
    return ref
        .read(receiverServiceSourceProvider)
        .ensureRegistered(serverUrl: serverUrl);
  }

  Future<void> setDiscoverable({required bool enabled}) {
    return ref
        .read(receiverServiceSourceProvider)
        .setDiscoverable(enabled: enabled);
  }

  Future<void> respondToOffer({required bool accept}) {
    return ref.read(receiverServiceSourceProvider).respondToOffer(accept: accept);
  }

  Future<void> cancelTransfer() {
    return ref.read(receiverServiceSourceProvider).cancelTransfer();
  }

  Future<List<NearbyReceiver>> scanNearby({
    required Duration timeout,
  }) {
    return ref.read(receiverServiceSourceProvider).scanNearby(timeout: timeout);
  }

  Future<void> shutdown() {
    return ref.read(receiverServiceSourceProvider).shutdown();
  }
}

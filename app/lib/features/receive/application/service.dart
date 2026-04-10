import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state.dart';

final receiverServiceProvider =
    NotifierProvider<ReceiverServiceController, ReceiverServiceState>(
  ReceiverServiceController.new,
);

class ReceiverServiceController extends Notifier<ReceiverServiceState> {
  Timer? _timer;
  int _stateIndex = 0;

  static const _states = <ReceiverServiceState>[
    ReceiverServiceState.ready(),
    ReceiverServiceState.unavailable(),
    ReceiverServiceState.registering(),
  ];

  @override
  ReceiverServiceState build() {
    ref.onDispose(() => _timer?.cancel());
    _timer ??= Timer.periodic(
      const Duration(milliseconds: 1400),
      (_) => advanceDemoState(),
    );
    _stateIndex = 0;
    return _states[_stateIndex];
  }

  void advanceDemoState() {
    _stateIndex = (_stateIndex + 1) % _states.length;
    state = _states[_stateIndex];
  }

  Future<void> setup({String? serverUrl}) async {}

  Future<void> ensureRegistered({String? serverUrl}) async {}

  Future<void> setDiscoverable({required bool enabled}) async {}

  Future<void> respondToOffer({required bool accept}) async {}

  Future<void> cancelTransfer() async {}

  Future<List<NearbyReceiver>> scanNearby({required Duration timeout}) async {
    return const [];
  }

  Future<void> shutdown() async {
    _timer?.cancel();
    _timer = null;
  }
}

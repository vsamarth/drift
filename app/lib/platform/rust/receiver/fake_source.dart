import 'dart:async';

import '../../../features/receive/application/state.dart';
import 'source.dart';

class FakeReceiverServiceSource implements ReceiverServiceSource {
  FakeReceiverServiceSource({
    ReceiverServiceState? initialState,
  }) : _state =
           initialState ??
           ReceiverServiceState.ready(code: 'ABC123', expiresAt: null);

  final StreamController<ReceiverServiceState> _stateController =
      StreamController<ReceiverServiceState>.broadcast(sync: true);

  ReceiverServiceState _state;

  @override
  ReceiverServiceState get currentState => _state;

  @override
  Stream<ReceiverServiceState> watchState() => Stream<ReceiverServiceState>.multi(
    (multi) {
      multi.add(_state);
      final subscription = _stateController.stream.listen(multi.add);
      multi.onCancel = subscription.cancel;
    },
  );

  void emit(ReceiverServiceState next) {
    _state = next;
    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
  }

  @override
  Future<void> setup({String? serverUrl}) async {}

  @override
  Future<void> ensureRegistered({String? serverUrl}) async {}

  @override
  Future<void> setDiscoverable({required bool enabled}) async {}

  @override
  Future<void> respondToOffer({required bool accept}) async {}

  @override
  Future<void> cancelTransfer() async {}

  @override
  Future<List<NearbyReceiver>> scanNearby({required Duration timeout}) async {
    return const [];
  }

  @override
  Future<void> shutdown() async {
    await _stateController.close();
  }
}

import '../../../features/receive/application/state.dart';

abstract class ReceiverServiceSource {
  ReceiverServiceState get currentState;

  Stream<ReceiverServiceState> watchState();

  Future<void> setup({String? serverUrl});

  Future<void> ensureRegistered({String? serverUrl});

  Future<void> setDiscoverable({required bool enabled});

  Future<void> respondToOffer({required bool accept});

  Future<void> cancelTransfer();

  Future<List<NearbyReceiver>> scanNearby({required Duration timeout});

  Future<void> shutdown();
}

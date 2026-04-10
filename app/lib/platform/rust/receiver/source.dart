import '../../../features/receive/application/state.dart';
import '../../../src/rust/api/receiver.dart' as rust_receiver;

abstract class ReceiverServiceSource {
  ReceiverServiceState get currentState;

  Stream<ReceiverServiceState> watchState();

  Stream<rust_receiver.ReceiverTransferEvent> watchIncomingTransfers();

  Future<void> setup({String? serverUrl});

  Future<void> ensureRegistered({String? serverUrl});

  Future<void> setDiscoverable({required bool enabled});

  Future<void> respondToOffer({required bool accept});

  Future<void> cancelTransfer();

  Future<List<NearbyReceiver>> scanNearby({required Duration timeout});

  Future<void> shutdown();
}

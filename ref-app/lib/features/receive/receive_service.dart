import '../../state/receiver_service_source.dart';
import '../../state/app_identity.dart';
import '../../src/rust/api/receiver.dart' as rust_receiver;

class ReceiveService {
  const ReceiveService(this._source);

  final ReceiverServiceSource _source;

  Stream<ReceiverBadgeState> watchBadge(DriftAppIdentity identity) {
    return _source.watchBadge(identity);
  }

  Stream<rust_receiver.ReceiverTransferEvent> watchIncomingTransfers(
    DriftAppIdentity identity,
  ) {
    return _source.watchIncomingTransfers(identity);
  }

  Future<void> setDiscoverable({required bool enabled}) {
    return _source.setDiscoverable(enabled: enabled);
  }

  Future<void> respondToOffer({required bool accept}) {
    return _source.respondToOffer(accept: accept);
  }

  Future<void> cancelTransfer() {
    return _source.cancelTransfer();
  }
}

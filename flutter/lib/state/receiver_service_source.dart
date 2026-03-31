import '../src/rust/api/receiver.dart' as rust_receiver;
import 'app_identity.dart';

class ReceiverBadgeState {
  const ReceiverBadgeState({
    required this.code,
    required this.status,
    this.expiresAt,
  });

  const ReceiverBadgeState.registering()
    : code = '......',
      status = 'Registering',
      expiresAt = null;

  const ReceiverBadgeState.unavailable()
    : code = '......',
      status = 'Unavailable',
      expiresAt = null;

  final String code;
  final String status;
  final String? expiresAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReceiverBadgeState &&
          runtimeType == other.runtimeType &&
          code == other.code &&
          status == other.status &&
          expiresAt == other.expiresAt;

  @override
  int get hashCode => Object.hash(code, status, expiresAt);
}

abstract class ReceiverServiceSource {
  Stream<ReceiverBadgeState> watchBadge(DriftAppIdentity identity);

  Stream<rust_receiver.ReceiverTransferEvent> watchIncomingTransfers(
    DriftAppIdentity identity,
  );

  Future<void> setDiscoverable({required bool enabled});

  Future<void> respondToOffer({required bool accept});
}

class LocalReceiverServiceSource implements ReceiverServiceSource {
  const LocalReceiverServiceSource();

  @override
  Stream<ReceiverBadgeState> watchBadge(DriftAppIdentity identity) {
    return rust_receiver
        .watchReceiverPairing(
          serverUrl: identity.serverUrl,
          downloadRoot: identity.downloadRoot,
          deviceName: identity.deviceName,
          deviceType: identity.deviceType,
        )
        .map(_mapPairingState);
  }

  @override
  Stream<rust_receiver.ReceiverTransferEvent> watchIncomingTransfers(
    DriftAppIdentity identity,
  ) {
    return rust_receiver.startReceiverTransferListener(
      serverUrl: identity.serverUrl,
      downloadRoot: identity.downloadRoot,
      deviceName: identity.deviceName,
      deviceType: identity.deviceType,
    );
  }

  @override
  Future<void> setDiscoverable({required bool enabled}) {
    return rust_receiver.setReceiverDiscoverable(enabled: enabled);
  }

  @override
  Future<void> respondToOffer({required bool accept}) {
    return rust_receiver.respondToReceiverOffer(accept: accept);
  }
}

ReceiverBadgeState _mapPairingState(rust_receiver.ReceiverPairingState state) {
  final code = (state.code ?? '').trim().toUpperCase();
  if (code.isEmpty) {
    return const ReceiverBadgeState.unavailable();
  }
  return ReceiverBadgeState(
    code: code,
    status: 'Ready',
    expiresAt: state.expiresAt,
  );
}

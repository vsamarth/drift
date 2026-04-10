import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../platform/rust/receiver/fake_source.dart';
import '../../../platform/rust/receiver/source.dart';
import '../../../src/rust/api/receiver.dart' as rust_receiver;
import 'identity.dart';
import 'manifest.dart';
import 'state.dart';

final transfersServiceSourceProvider = Provider<ReceiverServiceSource>(
  (ref) => FakeReceiverServiceSource(),
);

final transfersServiceProvider =
    NotifierProvider<TransfersServiceController, TransferSessionState>(
      TransfersServiceController.new,
    );

class TransfersServiceController extends Notifier<TransferSessionState> {
  StreamSubscription<rust_receiver.ReceiverTransferEvent>? _subscription;
  TransferIncomingOffer? _incomingOffer;

  @override
  TransferSessionState build() {
    final source = ref.watch(transfersServiceSourceProvider);
    _subscription?.cancel();
    _subscription = source.watchIncomingTransfers().listen((event) {
      switch (event.phase) {
        case rust_receiver.ReceiverTransferPhase.offerReady:
          _incomingOffer = _mapIncomingOffer(event);
          state = TransferSessionState.offerPending(offer: _incomingOffer!);
          return;
        case rust_receiver.ReceiverTransferPhase.connecting:
          if (_incomingOffer != null) {
            state = TransferSessionState.offerPending(offer: _incomingOffer!);
          }
          return;
        case rust_receiver.ReceiverTransferPhase.receiving:
          _incomingOffer ??= _mapIncomingOffer(event);
          state = TransferSessionState.receiving(
            offer: _incomingOffer!,
            progress: _mapProgress(event),
          );
          return;
        case rust_receiver.ReceiverTransferPhase.completed:
          final offer = _incomingOffer ?? _mapIncomingOffer(event);
          state = TransferSessionState.completed(
            offer: offer,
            result: _mapResult(event),
          );
          _incomingOffer = null;
          return;
        case rust_receiver.ReceiverTransferPhase.failed:
          final offer = _incomingOffer ?? _mapIncomingOffer(event);
          state = TransferSessionState.failed(
            offer: offer,
            errorMessage: event.error?.message ?? event.statusMessage,
          );
          _incomingOffer = null;
          return;
        case rust_receiver.ReceiverTransferPhase.cancelled:
        case rust_receiver.ReceiverTransferPhase.declined:
          state = const TransferSessionState.idle();
          _incomingOffer = null;
          return;
      }
    });
    ref.onDispose(() => _subscription?.cancel());
    return const TransferSessionState.idle();
  }

  Future<void> acceptOffer() {
    final source = ref.read(transfersServiceSourceProvider);
    final offer = state.offer ?? _incomingOffer ?? _offerFromFakeSource(source);
    if (offer != null) {
      state = TransferSessionState.receiving(
        offer: offer,
        progress: TransferTransferProgress(
          bytesTransferred: BigInt.zero,
          totalBytes: offer.manifest.totalSizeBytes,
          completedFiles: 0,
          totalFiles: offer.manifest.itemCount,
        ),
      );
    }
    return source.respondToOffer(accept: true);
  }

  Future<void> declineOffer() {
    final source = ref.read(transfersServiceSourceProvider);
    state = const TransferSessionState.idle();
    _incomingOffer = null;
    return source.respondToOffer(accept: false);
  }

  Future<void> cancelTransfer() {
    final source = ref.read(transfersServiceSourceProvider);
    state = const TransferSessionState.idle();
    _incomingOffer = null;
    return source.cancelTransfer();
  }

  TransferIncomingOffer _mapIncomingOffer(
    rust_receiver.ReceiverTransferEvent event,
  ) {
    return TransferIncomingOffer(
      sender: TransferIdentity(
        role: TransferRole.sender,
        // The current Flutter bridge does not surface endpoint IDs on transfer events yet.
        endpointId: '',
        deviceName: event.senderName,
        deviceType: _mapDeviceType(event.senderDeviceType),
      ),
      manifest: TransferManifest(
        items: event.files
            .map(
              (file) =>
                  TransferManifestItem(path: file.path, sizeBytes: file.size),
            )
            .toList(growable: false),
      ),
      destinationLabel: event.destinationLabel,
      saveRootLabel: event.saveRootLabel,
      statusMessage: event.statusMessage,
    );
  }

  TransferTransferProgress _mapProgress(
    rust_receiver.ReceiverTransferEvent event,
  ) {
    final snapshot = event.snapshot;
    return TransferTransferProgress(
      bytesTransferred: snapshot == null
          ? event.bytesReceived
          : snapshot.bytesTransferred,
      totalBytes: snapshot == null ? event.totalSizeBytes : snapshot.totalBytes,
      completedFiles: snapshot == null ? 0 : snapshot.completedFiles,
      totalFiles: snapshot == null
          ? event.itemCount.toInt()
          : snapshot.totalFiles,
      speedLabel: snapshot == null ? null : _formatRate(snapshot.bytesPerSec),
      etaLabel: snapshot == null ? null : _formatEta(snapshot.etaSeconds),
    );
  }

  TransferTransferResult _mapResult(rust_receiver.ReceiverTransferEvent event) {
    final snapshot = event.snapshot;
    return TransferTransferResult(
      bytesTransferred: snapshot == null
          ? event.bytesReceived
          : snapshot.bytesTransferred,
      totalBytes: snapshot == null ? event.totalSizeBytes : snapshot.totalBytes,
      completedFiles: snapshot == null
          ? event.itemCount.toInt()
          : snapshot.completedFiles,
      totalFiles: snapshot == null
          ? event.itemCount.toInt()
          : snapshot.totalFiles,
    );
  }

  DeviceType _mapDeviceType(String value) {
    switch (value.trim().toLowerCase()) {
      case 'phone':
        return DeviceType.phone;
      case 'laptop':
      default:
        return DeviceType.laptop;
    }
  }

  String? _formatRate(BigInt? bytesPerSec) {
    if (bytesPerSec == null) {
      return null;
    }
    return '$bytesPerSec B/s';
  }

  String? _formatEta(BigInt? etaSeconds) {
    if (etaSeconds == null) {
      return null;
    }
    return '${etaSeconds}s left';
  }

  TransferIncomingOffer? _offerFromFakeSource(ReceiverServiceSource source) {
    if (source is! FakeReceiverServiceSource) {
      return null;
    }

    final senderName = source.lastIncomingSenderName;
    if (senderName == null) {
      return null;
    }

    return TransferIncomingOffer(
      sender: TransferIdentity(
        role: TransferRole.sender,
        endpointId: source.lastIncomingSenderEndpointId ?? '',
        deviceName: senderName,
        deviceType: DeviceType.laptop,
      ),
      manifest: TransferManifest(
        items: (source.lastIncomingFiles ?? const [])
            .map(
              (file) =>
                  TransferManifestItem(path: file.path, sizeBytes: file.size),
            )
            .toList(growable: false),
      ),
      destinationLabel: 'Downloads',
      saveRootLabel: 'Downloads',
      statusMessage: 'Incoming offer',
    );
  }
}

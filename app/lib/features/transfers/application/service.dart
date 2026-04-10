import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../platform/rust/receiver/fake_source.dart';
import '../../../platform/rust/receiver/source.dart';
import '../../../src/rust/api/receiver.dart' as rust_receiver;
import 'state.dart';

final transfersServiceSourceProvider = Provider<ReceiverServiceSource>(
  (ref) => FakeReceiverServiceSource(),
);

final transfersServiceProvider = NotifierProvider<
  TransfersServiceController,
  TransfersServiceState
>(TransfersServiceController.new);

class TransfersServiceController extends Notifier<TransfersServiceState> {
  StreamSubscription<rust_receiver.ReceiverTransferEvent>? _subscription;
  TransferIncomingOfferState? _incomingOffer;

  @override
  TransfersServiceState build() {
    final source = ref.watch(transfersServiceSourceProvider);
    _subscription?.cancel();
    _subscription = source.watchIncomingTransfers().listen((event) {
      debugPrint(
        '[transfers] incoming event: '
        'sender=${event.senderName} phase=${event.phase.name}',
      );
      switch (event.phase) {
        case rust_receiver.ReceiverTransferPhase.offerReady:
          _incomingOffer = TransferIncomingOfferState(
            senderName: event.senderName,
          );
          state = TransfersServiceState.offerPending(
            senderName: event.senderName,
          );
          return;
        case rust_receiver.ReceiverTransferPhase.connecting:
          if (_incomingOffer != null) {
            state = TransfersServiceState.offerPending(
              senderName: _incomingOffer!.senderName,
            );
          }
          return;
        case rust_receiver.ReceiverTransferPhase.receiving:
          _incomingOffer = TransferIncomingOfferState(
            senderName: event.senderName,
          );
          state = TransfersServiceState.receiving(
            senderName: event.senderName,
          );
          return;
        case rust_receiver.ReceiverTransferPhase.completed:
          state = TransfersServiceState.completed(
            senderName: _incomingOffer?.senderName,
          );
          _incomingOffer = null;
          return;
        case rust_receiver.ReceiverTransferPhase.failed:
        case rust_receiver.ReceiverTransferPhase.cancelled:
        case rust_receiver.ReceiverTransferPhase.declined:
          state = TransfersServiceState.failed(
            senderName: _incomingOffer?.senderName,
          );
          _incomingOffer = null;
          return;
      }
    });
    ref.onDispose(() => _subscription?.cancel());
    return const TransfersServiceState.idle();
  }

  Future<void> acceptOffer() {
    final source = ref.read(transfersServiceSourceProvider);
    final senderName =
        (source is FakeReceiverServiceSource)
            ? source.lastIncomingSenderName
            : null;
    state = TransfersServiceState.receiving(
      senderName: senderName ?? state.incomingOffer?.senderName ?? '',
    );
    return source.respondToOffer(accept: true);
  }

  Future<void> declineOffer() {
    final source = ref.read(transfersServiceSourceProvider);
    state = const TransfersServiceState.idle();
    _incomingOffer = null;
    return source.respondToOffer(accept: false);
  }
}

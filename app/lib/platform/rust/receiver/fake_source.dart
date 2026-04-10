import 'dart:async';

import '../../../features/receive/application/state.dart';
import '../../../src/rust/api/receiver.dart' as rust_receiver;
import 'source.dart';

class FakeReceiverServiceSource implements ReceiverServiceSource {
  FakeReceiverServiceSource({
    ReceiverServiceState? initialState,
  }) : _state =
           initialState ??
           ReceiverServiceState.ready(code: 'ABC123', expiresAt: null);

  final StreamController<ReceiverServiceState> _stateController =
      StreamController<ReceiverServiceState>.broadcast(sync: true);
  final StreamController<rust_receiver.ReceiverTransferEvent>
      _incomingController =
      StreamController<rust_receiver.ReceiverTransferEvent>.broadcast(
        sync: true,
      );

  ReceiverServiceState _state;
  bool? lastRespondToOfferAccept;
  int respondToOfferCalls = 0;
  String? lastIncomingSenderName;
  String? lastIncomingSenderEndpointId;
  List<rust_receiver.ReceiverTransferFile>? lastIncomingFiles;

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

  @override
  Stream<rust_receiver.ReceiverTransferEvent> watchIncomingTransfers() =>
      Stream<rust_receiver.ReceiverTransferEvent>.multi((multi) {
        final subscription = _incomingController.stream.listen(multi.add);
        multi.onCancel = subscription.cancel;
      });

  void emit(ReceiverServiceState next) {
    _state = next;
    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
  }

  void emitIncomingOffer({
    required String senderName,
    String senderEndpointId = 'endpoint-1',
    String senderDeviceType = 'laptop',
    String destinationLabel = 'Downloads',
    String saveRootLabel = 'Downloads',
    String statusMessage = 'Incoming offer',
    List<rust_receiver.ReceiverTransferFile>? files,
  }) {
    if (_incomingController.isClosed) {
      return;
    }
    final incomingFiles =
        files ??
        [
          rust_receiver.ReceiverTransferFile(
            path: 'report.pdf',
            size: BigInt.from(1024),
          ),
          rust_receiver.ReceiverTransferFile(
            path: 'photo.jpg',
            size: BigInt.from(2048),
          ),
    ];
    lastIncomingSenderEndpointId = senderEndpointId;
    lastIncomingSenderName = senderName;
    lastIncomingFiles = incomingFiles;
    _incomingController.add(
      rust_receiver.ReceiverTransferEvent(
        phase: rust_receiver.ReceiverTransferPhase.offerReady,
        senderName: senderName,
        senderDeviceType: senderDeviceType,
        destinationLabel: destinationLabel,
        saveRootLabel: saveRootLabel,
        statusMessage: statusMessage,
        itemCount: BigInt.from(incomingFiles.length),
        totalSizeBytes: incomingFiles.fold<BigInt>(
          BigInt.zero,
          (sum, file) => sum + file.size,
        ),
        bytesReceived: BigInt.zero,
        totalSizeLabel: '0 B',
        files: incomingFiles,
        error: null,
      ),
    );
  }

  @override
  Future<void> setup({String? serverUrl}) async {}

  @override
  Future<void> ensureRegistered({String? serverUrl}) async {}

  @override
  Future<void> setDiscoverable({required bool enabled}) async {}

  @override
  Future<void> respondToOffer({required bool accept}) async {
    lastRespondToOfferAccept = accept;
    respondToOfferCalls += 1;
  }

  @override
  Future<void> cancelTransfer() async {}

  @override
  Future<List<NearbyReceiver>> scanNearby({required Duration timeout}) async {
    return const [];
  }

  @override
  Future<void> shutdown() async {
    await _stateController.close();
    await _incomingController.close();
  }
}

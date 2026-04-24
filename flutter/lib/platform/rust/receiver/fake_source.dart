import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../features/receive/application/state.dart';
import '../../../src/rust/api/transfer.dart' as rust_transfer;
import '../../../src/rust/api/receiver.dart' as rust_receiver;
import 'source.dart';

class FakeReceiverServiceSource implements ReceiverServiceSource {
  FakeReceiverServiceSource({
    ReceiverServiceState? initialState,
    List<NearbyReceiver> nearbyResults = const [],
  }) : _state =
           initialState ??
           ReceiverServiceState.ready(code: 'ABC123', expiresAt: null),
       _nearbyResults = nearbyResults;

  final StreamController<ReceiverServiceState> _stateController =
      StreamController<ReceiverServiceState>.broadcast(sync: true);
  final StreamController<rust_receiver.ReceiverTransferEvent>
  _incomingController =
      StreamController<rust_receiver.ReceiverTransferEvent>.broadcast(
        sync: true,
      );

  ReceiverServiceState _state;
  final List<NearbyReceiver> _nearbyResults;
  bool? lastDiscoverableEnabled;
  int setDiscoverableCalls = 0;
  bool? lastRespondToOfferAccept;
  int respondToOfferCalls = 0;
  String? lastIncomingSenderName;
  String? lastIncomingSenderEndpointId;
  List<rust_receiver.ReceiverTransferFile>? lastIncomingFiles;
  rust_receiver.ReceiverTransferEvent? _lastIncomingEvent;
  String? lastUpdatedDeviceName;
  String? lastUpdatedServerUrl;

  @override
  ReceiverServiceState get currentState => _state;

  @override
  Stream<ReceiverServiceState> watchState() =>
      Stream<ReceiverServiceState>.multi((multi) {
        multi.add(_state);
        final subscription = _stateController.stream.listen(multi.add);
        multi.onCancel = subscription.cancel;
      });

  @override
  Stream<rust_receiver.ReceiverTransferEvent> watchIncomingTransfers() =>
      Stream<rust_receiver.ReceiverTransferEvent>.multi((multi) {
        if (_lastIncomingEvent != null) {
          multi.add(_lastIncomingEvent!);
        }
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
    _lastIncomingEvent = rust_receiver.ReceiverTransferEvent(
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
    );
    _incomingController.add(_lastIncomingEvent!);
  }

  void emitCompletedTransfer({
    required String senderName,
    String senderDeviceType = 'laptop',
    String destinationLabel = 'Downloads',
    String saveRootLabel = 'Downloads',
    String statusMessage = 'Transfer complete',
  }) {
    if (_incomingController.isClosed) {
      return;
    }
    final completedFiles =
        lastIncomingFiles ??
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
    lastIncomingSenderName = senderName;
    lastIncomingFiles = completedFiles;
    _lastIncomingEvent = rust_receiver.ReceiverTransferEvent(
      phase: rust_receiver.ReceiverTransferPhase.completed,
      senderName: senderName,
      senderDeviceType: senderDeviceType,
      destinationLabel: destinationLabel,
      saveRootLabel: saveRootLabel,
      statusMessage: statusMessage,
      itemCount: BigInt.from(completedFiles.length),
      totalSizeBytes: completedFiles.fold<BigInt>(
        BigInt.zero,
        (sum, file) => sum + file.size,
      ),
      bytesReceived: completedFiles.fold<BigInt>(
        BigInt.zero,
        (sum, file) => sum + file.size,
      ),
      snapshot: rust_transfer.TransferSnapshotData(
        sessionId: 'completed-session',
        phase: rust_transfer.TransferPhaseData.completed,
        totalFiles: completedFiles.length,
        completedFiles: completedFiles.length,
        totalBytes: completedFiles.fold<BigInt>(
          BigInt.zero,
          (sum, file) => sum + file.size,
        ),
        bytesTransferred: completedFiles.fold<BigInt>(
          BigInt.zero,
          (sum, file) => sum + file.size,
        ),
        bytesPerSec: null,
        etaSeconds: null,
      ),
      totalSizeLabel:
          '${completedFiles.fold<BigInt>(BigInt.zero, (sum, file) => sum + file.size)} B',
      files: completedFiles,
      error: null,
    );
    _incomingController.add(_lastIncomingEvent!);
  }

  void emitCancelledTransfer({
    required String senderName,
    String senderDeviceType = 'laptop',
    String destinationLabel = 'Downloads',
    String saveRootLabel = 'Downloads',
    String statusMessage =
        'Drift stopped receiving before all files were saved.',
  }) {
    if (_incomingController.isClosed) {
      return;
    }
    final cancelledFiles =
        lastIncomingFiles ??
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
    lastIncomingSenderName = senderName;
    lastIncomingFiles = cancelledFiles;
    _lastIncomingEvent = rust_receiver.ReceiverTransferEvent(
      phase: rust_receiver.ReceiverTransferPhase.cancelled,
      senderName: senderName,
      senderDeviceType: senderDeviceType,
      destinationLabel: destinationLabel,
      saveRootLabel: saveRootLabel,
      statusMessage: statusMessage,
      itemCount: BigInt.from(cancelledFiles.length),
      totalSizeBytes: cancelledFiles.fold<BigInt>(
        BigInt.zero,
        (sum, file) => sum + file.size,
      ),
      bytesReceived: cancelledFiles.fold<BigInt>(
        BigInt.zero,
        (sum, file) => sum + file.size,
      ),
      totalSizeLabel:
          '${cancelledFiles.fold<BigInt>(BigInt.zero, (sum, file) => sum + file.size)} B',
      files: cancelledFiles,
      error: null,
    );
    _incomingController.add(_lastIncomingEvent!);
  }

  @override
  Future<void> setup({String? serverUrl}) async {}

  @override
  Future<void> ensureRegistered({String? serverUrl}) async {}

  @override
  Future<void> updateIdentity({
    required String deviceName,
    required String downloadRoot,
    String? serverUrl,
  }) async {
    lastUpdatedDeviceName = deviceName;
    lastUpdatedServerUrl = serverUrl;
  }

  @override
  Future<void> setDiscoverable({required bool enabled}) async {
    debugPrint(
      '[receiver-fake] discoverable ${enabled ? 'enabled' : 'disabled'}',
    );
    lastDiscoverableEnabled = enabled;
    setDiscoverableCalls += 1;
  }

  @override
  Future<void> respondToOffer({required bool accept}) async {
    lastRespondToOfferAccept = accept;
    respondToOfferCalls += 1;
  }

  @override
  Future<void> cancelTransfer() async {
    if (lastIncomingSenderName == null) {
      return;
    }
    emitCancelledTransfer(senderName: lastIncomingSenderName!);
  }

  @override
  Future<List<NearbyReceiver>> scanNearby({required Duration timeout}) async {
    return _nearbyResults;
  }

  @override
  Future<void> shutdown() async {
    await _stateController.close();
    await _incomingController.close();
  }
}

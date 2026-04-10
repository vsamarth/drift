import 'dart:async';

import 'package:drift_app/core/models/transfer_models.dart';
import 'package:drift_app/platform/send_item_source.dart';
import 'package:drift_app/platform/send_transfer_source.dart';
import 'package:drift_app/state/app_identity.dart';
import 'package:drift_app/state/drift_app_notifier.dart';
import 'package:drift_app/state/drift_app_state.dart';
import 'package:drift_app/state/nearby_discovery_source.dart';
import 'package:drift_app/state/receiver_service_source.dart';

const List<TransferItemViewData> _sampleSendItems = [
  TransferItemViewData(
    name: 'sample.txt',
    path: 'sample.txt',
    size: '18 KB',
    kind: TransferItemKind.file,
  ),
];

const TransferItemViewData _extraSendItem = TransferItemViewData(
  name: 'notes.pdf',
  path: 'notes.pdf',
  size: '12 KB',
  kind: TransferItemKind.file,
);

class FakeSendAppNotifier extends DriftAppNotifier {
  FakeSendAppNotifier(this._state);

  DriftAppState _state;

  @override
  DriftAppState build() => _state;

  void setState(DriftAppState nextState) {
    _state = nextState;
    state = nextState;
  }
}

class FakeSendItemSource implements SendItemSource {
  FakeSendItemSource({
    List<List<String>>? pickResponses,
    Map<String, TransferItemViewData>? itemCatalog,
    this.pickFilesError,
  }) : _pickResponses =
           pickResponses ??
           const [
             ['sample.txt'],
           ],
       _itemCatalog =
           itemCatalog ??
           {'sample.txt': _sampleSendItems[0], 'notes.pdf': _extraSendItem};

  final List<List<String>> _pickResponses;
  final Map<String, TransferItemViewData> _itemCatalog;
  final Object? pickFilesError;
  int _pickIndex = 0;
  int pickFilesCalls = 0;
  int pickAdditionalPathsCalls = 0;
  int pickAdditionalFilesCalls = 0;
  int loadPathsCalls = 0;
  int appendPathsCalls = 0;
  int removePathCalls = 0;

  @override
  Future<List<TransferItemViewData>> pickFiles() async {
    pickFilesCalls += 1;
    return pickFilesError == null
        ? _mapPaths(_nextPickResponse())
        : Future<List<TransferItemViewData>>.error(pickFilesError!);
  }

  @override
  Future<List<String>> pickAdditionalPaths() async {
    pickAdditionalPathsCalls += 1;
    return _nextPickResponse();
  }

  @override
  Future<List<TransferItemViewData>> pickAdditionalFiles({
    required List<String> existingPaths,
  }) async {
    pickAdditionalFilesCalls += 1;
    return appendPaths(
      existingPaths: existingPaths,
      incomingPaths: _nextPickResponse(),
    );
  }

  @override
  Future<List<TransferItemViewData>> loadPaths(List<String> paths) async {
    loadPathsCalls += 1;
    return _mapPaths(paths);
  }

  @override
  Future<List<TransferItemViewData>> appendPaths({
    required List<String> existingPaths,
    required List<String> incomingPaths,
  }) async {
    appendPathsCalls += 1;
    final merged = <String>[];
    final seen = <String>{};
    for (final path in [...existingPaths, ...incomingPaths]) {
      if (seen.add(path)) {
        merged.add(path);
      }
    }
    return _mapPaths(merged);
  }

  @override
  Future<List<TransferItemViewData>> removePath({
    required List<String> existingPaths,
    required String removedPath,
  }) async {
    removePathCalls += 1;
    return _mapPaths(
      existingPaths
          .where((path) => path != removedPath)
          .toList(growable: false),
    );
  }

  List<String> _nextPickResponse() {
    final index = _pickIndex < _pickResponses.length
        ? _pickIndex
        : _pickResponses.length - 1;
    _pickIndex += 1;
    return _pickResponses[index];
  }

  List<TransferItemViewData> _mapPaths(List<String> paths) {
    final seen = <String>{};
    return List<TransferItemViewData>.unmodifiable(
      paths.where(seen.add).map((path) => _itemCatalog[path]!).toList(),
    );
  }
}

class FakeSendTransferSource implements SendTransferSource {
  FakeSendTransferSource({this.cancelError});

  SendTransferRequestData? lastRequest;
  int startTransferCalls = 0;
  int cancelTransferCalls = 0;
  final StreamController<SendTransferUpdate> controller =
      StreamController<SendTransferUpdate>.broadcast();
  final Object? cancelError;

  @override
  Stream<SendTransferUpdate> startTransfer(SendTransferRequestData request) {
    startTransferCalls += 1;
    lastRequest = request;
    return controller.stream;
  }

  @override
  Future<void> cancelTransfer() async {
    cancelTransferCalls += 1;
    if (cancelError != null) {
      throw cancelError!;
    }
  }

  Future<void> dispose() async {
    await controller.close();
  }
}

class FakeNearbyDiscoverySource implements NearbyDiscoverySource {
  FakeNearbyDiscoverySource({this.scanHandler, this.destinations = const []});

  int scanCount = 0;
  final List<SendDestinationViewData> destinations;
  Future<List<SendDestinationViewData>> Function()? scanHandler;

  @override
  Future<List<SendDestinationViewData>> scan({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    scanCount += 1;
    if (scanHandler != null) {
      return await scanHandler!();
    }
    return destinations;
  }
}

DriftAppState buildSendDraftState({
  String deviceName = 'Drift Device',
  String deviceType = 'laptop',
  String downloadRoot = '/tmp/Downloads',
}) {
  return DriftAppState(
    identity: DriftAppIdentity(
      deviceName: deviceName,
      deviceType: deviceType,
      downloadRoot: downloadRoot,
    ),
    receiverBadge: const ReceiverBadgeState(
      code: 'F9P2Q1',
      status: 'Ready',
      phase: ReceiverBadgePhase.ready,
    ),
    session: const SendDraftSession(
      items: [
        TransferItemViewData(
          name: 'sample.txt',
          path: 'sample.txt',
          size: '18 KB',
          kind: TransferItemKind.file,
        ),
      ],
      isInspecting: false,
      nearbyDestinations: [
        SendDestinationViewData(
          name: 'Lab Mac',
          kind: SendDestinationKind.laptop,
          lanTicket: 'ticket-123',
          lanFullname: 'lab-mac._drift._udp.local.',
        ),
      ],
      nearbyScanInFlight: false,
      nearbyScanCompletedOnce: true,
      destinationCode: '',
    ),
    animateSendingConnection: false,
  );
}

DriftAppState buildSendTransferState() {
  return DriftAppState(
    identity: const DriftAppIdentity(
      deviceName: 'Drift Device',
      deviceType: 'laptop',
      downloadRoot: '/tmp/Downloads',
    ),
    receiverBadge: const ReceiverBadgeState(
      code: 'F9P2Q1',
      status: 'Ready',
      phase: ReceiverBadgePhase.ready,
    ),
    session: const SendTransferSession(
      phase: SendTransferSessionPhase.sending,
      items: [
        TransferItemViewData(
          name: 'sample.txt',
          path: 'sample.txt',
          size: '18 KB',
          kind: TransferItemKind.file,
        ),
      ],
      summary: TransferSummaryViewData(
        itemCount: 1,
        totalSize: '18 KB',
        code: 'AB2CD3',
        expiresAt: '',
        destinationLabel: 'Maya’s iPhone',
        statusMessage: 'Sending files...',
      ),
      payloadBytesSent: 9 * 1024,
      payloadTotalBytes: 18 * 1024,
      payloadSpeedLabel: '1 MB/s',
      payloadEtaLabel: '1 min',
      remoteDeviceType: 'phone',
    ),
    animateSendingConnection: false,
  );
}

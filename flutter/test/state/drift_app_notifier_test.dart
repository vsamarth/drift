import 'dart:async';

import 'package:drift_app/core/models/transfer_models.dart';
import 'package:drift_app/platform/send_item_source.dart';
import 'package:drift_app/platform/send_transfer_source.dart';
import 'package:drift_app/state/app_identity.dart';
import 'package:drift_app/state/drift_app_state.dart';
import 'package:drift_app/state/drift_providers.dart';
import 'package:drift_app/state/nearby_discovery_source.dart';
import 'package:drift_app/state/receiver_service_source.dart';
import 'package:drift_app/state/settings_store.dart';
import 'package:drift_app/src/rust/api/receiver.dart' as rust_receiver;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
  size: '42 KB',
  kind: TransferItemKind.file,
);

Future<void> _flushAsyncWork(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

ProviderContainer _buildContainer({
  SendItemSource? sendItemSource,
  SendTransferSource? sendTransferSource,
  NearbyDiscoverySource? nearbyDiscoverySource,
  ReceiverServiceSource? receiverServiceSource,
  bool enableIdleIncomingListener = false,
}) {
  return ProviderContainer(
    overrides: [
      driftSettingsStoreProvider.overrideWith(
        (ref) => DriftSettingsStore.inMemory(),
      ),
      initialDriftAppIdentityProvider.overrideWith(
        (ref) => const DriftAppIdentity(
          deviceName: 'Drift Device',
          deviceType: 'laptop',
          downloadRoot: '/tmp/Downloads',
        ),
      ),
      driftAppIdentityProvider.overrideWith(
        (ref) => const DriftAppIdentity(
          deviceName: 'Drift Device',
          deviceType: 'laptop',
          downloadRoot: '/tmp/Downloads',
        ),
      ),
      sendItemSourceProvider.overrideWith(
        (ref) => sendItemSource ?? FakeSendItemSource(),
      ),
      sendTransferSourceProvider.overrideWith(
        (ref) => sendTransferSource ?? FakeSendTransferSource(),
      ),
      nearbyDiscoverySourceProvider.overrideWith(
        (ref) => nearbyDiscoverySource ?? FakeNearbyDiscoverySource(),
      ),
      receiverServiceSourceProvider.overrideWith(
        (ref) => receiverServiceSource ?? FakeReceiverServiceSource(),
      ),
      animateSendingConnectionProvider.overrideWith((ref) => false),
      enableIdleIncomingListenerProvider.overrideWith(
        (ref) => enableIdleIncomingListener,
      ),
    ],
  );
}

class FakeSendItemSource implements SendItemSource {
  FakeSendItemSource({
    List<List<String>>? pickResponses,
    Map<String, TransferItemViewData>? itemCatalog,
    this.appendPathsHandler,
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
  final Future<List<TransferItemViewData>> Function({
    required List<String> existingPaths,
    required List<String> incomingPaths,
  })?
  appendPathsHandler;
  int _pickIndex = 0;

  @override
  Future<List<String>> pickAdditionalPaths() async => _nextPickResponse();

  @override
  Future<List<TransferItemViewData>> pickAdditionalFiles({
    required List<String> existingPaths,
  }) async {
    return appendPaths(
      existingPaths: existingPaths,
      incomingPaths: _nextPickResponse(),
    );
  }

  @override
  Future<List<TransferItemViewData>> appendPaths({
    required List<String> existingPaths,
    required List<String> incomingPaths,
  }) async {
    if (appendPathsHandler != null) {
      return appendPathsHandler!(
        existingPaths: existingPaths,
        incomingPaths: incomingPaths,
      );
    }
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
  Future<List<TransferItemViewData>> loadPaths(List<String> paths) async =>
      _mapPaths(paths);

  @override
  Future<List<TransferItemViewData>> pickFiles() async =>
      _mapPaths(_nextPickResponse());

  @override
  Future<List<TransferItemViewData>> removePath({
    required List<String> existingPaths,
    required String removedPath,
  }) async {
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
  SendTransferRequestData? lastRequest;
  final StreamController<SendTransferUpdate> controller =
      StreamController<SendTransferUpdate>.broadcast();

  @override
  Stream<SendTransferUpdate> startTransfer(SendTransferRequestData request) {
    lastRequest = request;
    return controller.stream;
  }

  Future<void> dispose() async {
    await controller.close();
  }
}

class FakeNearbyDiscoverySource implements NearbyDiscoverySource {
  FakeNearbyDiscoverySource({this.scanHandler});

  int scanCount = 0;
  Future<List<SendDestinationViewData>> Function()? scanHandler;

  @override
  Future<List<SendDestinationViewData>> scan({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    scanCount += 1;
    return await (scanHandler?.call() ?? Future.value(const []));
  }
}

class FakeReceiverServiceSource implements ReceiverServiceSource {
  FakeReceiverServiceSource({
    this.initialBadge = const ReceiverBadgeState(
      code: 'F9P2Q1',
      status: 'Ready',
      phase: ReceiverBadgePhase.ready,
    ),
  });

  final ReceiverBadgeState initialBadge;
  final List<bool> discoverableCalls = <bool>[];
  final List<bool> respondToOfferCalls = <bool>[];
  final StreamController<ReceiverBadgeState> badgeController =
      StreamController<ReceiverBadgeState>.broadcast();
  final StreamController<rust_receiver.ReceiverTransferEvent>
  incomingController =
      StreamController<rust_receiver.ReceiverTransferEvent>.broadcast();

  @override
  Future<void> respondToOffer({required bool accept}) async {
    respondToOfferCalls.add(accept);
  }

  @override
  Future<void> setDiscoverable({required bool enabled}) async {
    discoverableCalls.add(enabled);
  }

  @override
  Stream<ReceiverBadgeState> watchBadge(DriftAppIdentity identity) async* {
    yield initialBadge;
    yield* badgeController.stream;
  }

  @override
  Stream<rust_receiver.ReceiverTransferEvent> watchIncomingTransfers(
    DriftAppIdentity identity,
  ) {
    return incomingController.stream;
  }

  Future<void> dispose() async {
    await badgeController.close();
    await incomingController.close();
  }
}

SendTransferUpdate _sendUpdate({
  required SendTransferUpdatePhase phase,
  String destinationLabel = 'Code AB2 CD3',
  String statusMessage = 'Request sent',
  int bytesSent = 0,
  int totalBytes = 0,
}) {
  return SendTransferUpdate(
    phase: phase,
    destinationLabel: destinationLabel,
    statusMessage: statusMessage,
    itemCount: 1,
    totalSize: '18 KB',
    bytesSent: bytesSent,
    totalBytes: totalBytes,
  );
}

rust_receiver.ReceiverTransferEvent _incomingOfferEvent() {
  return rust_receiver.ReceiverTransferEvent(
    phase: rust_receiver.ReceiverTransferPhase.offerReady,
    senderName: 'Maya',
    senderDeviceType: 'phone',
    destinationLabel: 'Downloads',
    saveRootLabel: 'Downloads',
    statusMessage: 'Maya wants to send you a file.',
    itemCount: BigInt.one,
    totalSizeBytes: BigInt.from(18 * 1024),
    bytesReceived: BigInt.zero,
    totalSizeLabel: '18 KB',
    files: [
      rust_receiver.ReceiverTransferFile(
        path: 'sample.txt',
        size: BigInt.from(18 * 1024),
      ),
    ],
  );
}

rust_receiver.ReceiverTransferEvent _incomingReceivingEvent({
  required BigInt receivedBytes,
}) {
  return rust_receiver.ReceiverTransferEvent(
    phase: rust_receiver.ReceiverTransferPhase.receiving,
    senderName: 'Maya',
    senderDeviceType: 'phone',
    destinationLabel: 'Downloads',
    saveRootLabel: 'Downloads',
    statusMessage: 'Receiving files...',
    itemCount: BigInt.one,
    totalSizeBytes: BigInt.from(18 * 1024),
    bytesReceived: receivedBytes,
    totalSizeLabel: '18 KB',
    files: const [],
  );
}

void main() {
  testWidgets(
    'selecting files enters send draft and disables discoverability',
    (tester) async {
      final receiverService = FakeReceiverServiceSource();
      final container = _buildContainer(receiverServiceSource: receiverService);
      addTearDown(receiverService.dispose);
      addTearDown(container.dispose);

      final notifier = container.read(driftAppNotifierProvider.notifier);
      await _flushAsyncWork(tester);

      notifier.pickSendItems();
      await _flushAsyncWork(tester);

      final state = container.read(driftAppNotifierProvider);
      expect(state.session, isA<SendDraftSession>());
      expect(state.discoverableEnabled, isFalse);
      expect(receiverService.discoverableCalls.last, isFalse);

      notifier.resetShell();
      await _flushAsyncWork(tester);
    },
  );

  testWidgets('add more appends instead of replacing', (tester) async {
    final receiverService = FakeReceiverServiceSource();
    final sendItemSource = FakeSendItemSource(
      pickResponses: const [
        ['sample.txt'],
        ['notes.pdf'],
      ],
    );
    final container = _buildContainer(
      receiverServiceSource: receiverService,
      sendItemSource: sendItemSource,
    );
    addTearDown(receiverService.dispose);
    addTearDown(container.dispose);

    final notifier = container.read(driftAppNotifierProvider.notifier);
    await _flushAsyncWork(tester);

    notifier.pickSendItems();
    await _flushAsyncWork(tester);
    notifier.appendSendItemsFromPicker();
    await _flushAsyncWork(tester);

    final state = container.read(driftAppNotifierProvider);
    expect(state.sendItems.map((item) => item.path).toList(), [
      'sample.txt',
      'notes.pdf',
    ]);

    notifier.resetShell();
    await _flushAsyncWork(tester);
  });

  testWidgets('add more shows pending items before inspection finishes', (
    tester,
  ) async {
    final receiverService = FakeReceiverServiceSource();
    final appendCompleter = Completer<List<TransferItemViewData>>();
    final sendItemSource = FakeSendItemSource(
      pickResponses: const [
        ['sample.txt'],
        ['notes.pdf'],
      ],
      appendPathsHandler:
          ({
            required List<String> existingPaths,
            required List<String> incomingPaths,
          }) {
            return appendCompleter.future;
          },
    );
    final container = _buildContainer(
      receiverServiceSource: receiverService,
      sendItemSource: sendItemSource,
    );
    addTearDown(receiverService.dispose);
    addTearDown(container.dispose);

    final notifier = container.read(driftAppNotifierProvider.notifier);
    await _flushAsyncWork(tester);

    notifier.pickSendItems();
    await _flushAsyncWork(tester);

    notifier.appendSendItemsFromPicker();
    await tester.pump();

    var state = container.read(driftAppNotifierProvider);
    expect(state.isInspectingSendItems, isTrue);
    expect(state.sendItems.map((item) => item.path).toList(), [
      'sample.txt',
      'notes.pdf',
    ]);
    expect(
      state.sendItems.firstWhere((item) => item.path == 'notes.pdf').size,
      'Adding...',
    );

    appendCompleter.complete([_sampleSendItems[0], _extraSendItem]);
    await _flushAsyncWork(tester);

    state = container.read(driftAppNotifierProvider);
    expect(state.isInspectingSendItems, isFalse);
    expect(
      state.sendItems.firstWhere((item) => item.path == 'notes.pdf').size,
      '42 KB',
    );

    notifier.resetShell();
    await _flushAsyncWork(tester);
  });

  testWidgets('removing one item keeps the rest', (tester) async {
    final receiverService = FakeReceiverServiceSource();
    final sendItemSource = FakeSendItemSource(
      pickResponses: const [
        ['sample.txt', 'notes.pdf'],
      ],
    );
    final container = _buildContainer(
      receiverServiceSource: receiverService,
      sendItemSource: sendItemSource,
    );
    addTearDown(receiverService.dispose);
    addTearDown(container.dispose);

    final notifier = container.read(driftAppNotifierProvider.notifier);
    await _flushAsyncWork(tester);

    notifier.pickSendItems();
    await _flushAsyncWork(tester);
    notifier.removeSendItem('sample.txt');
    await _flushAsyncWork(tester);

    final state = container.read(driftAppNotifierProvider);
    expect(state.session, isA<SendDraftSession>());
    expect(state.sendItems.map((item) => item.path).toList(), ['notes.pdf']);

    notifier.resetShell();
    await _flushAsyncWork(tester);
  });

  testWidgets('removing the last item returns to idle', (tester) async {
    final receiverService = FakeReceiverServiceSource();
    final container = _buildContainer(receiverServiceSource: receiverService);
    addTearDown(receiverService.dispose);
    addTearDown(container.dispose);

    final notifier = container.read(driftAppNotifierProvider.notifier);
    await _flushAsyncWork(tester);

    notifier.pickSendItems();
    await _flushAsyncWork(tester);
    notifier.removeSendItem('sample.txt');
    await _flushAsyncWork(tester);

    final state = container.read(driftAppNotifierProvider);
    expect(state.session, isA<IdleSession>());
  });

  testWidgets('dropped duplicate paths do not duplicate rows', (tester) async {
    final receiverService = FakeReceiverServiceSource();
    final container = _buildContainer(receiverServiceSource: receiverService);
    addTearDown(receiverService.dispose);
    addTearDown(container.dispose);

    final notifier = container.read(driftAppNotifierProvider.notifier);
    await _flushAsyncWork(tester);

    notifier.pickSendItems();
    await _flushAsyncWork(tester);
    notifier.appendDroppedSendItems(const ['sample.txt']);
    await _flushAsyncWork(tester);

    final state = container.read(driftAppNotifierProvider);
    expect(state.sendItems.map((item) => item.path).toList(), ['sample.txt']);

    notifier.resetShell();
    await _flushAsyncWork(tester);
  });

  testWidgets('canceling send restores discoverability', (tester) async {
    final receiverService = FakeReceiverServiceSource();
    final container = _buildContainer(receiverServiceSource: receiverService);
    addTearDown(receiverService.dispose);
    addTearDown(container.dispose);

    final notifier = container.read(driftAppNotifierProvider.notifier);
    await _flushAsyncWork(tester);

    notifier.pickSendItems();
    await _flushAsyncWork(tester);
    notifier.clearSendFlow();
    await _flushAsyncWork(tester);

    final state = container.read(driftAppNotifierProvider);
    expect(state.session, isA<IdleSession>());
    expect(state.discoverableEnabled, isTrue);
    expect(receiverService.discoverableCalls.last, isTrue);
  });

  testWidgets(
    'nearby scans only in send draft and stale scan results are ignored',
    (tester) async {
      final receiverService = FakeReceiverServiceSource();
      final nearbyResults = Completer<List<SendDestinationViewData>>();
      final nearbyDiscovery = FakeNearbyDiscoverySource(
        scanHandler: () => nearbyResults.future,
      );
      final container = _buildContainer(
        receiverServiceSource: receiverService,
        nearbyDiscoverySource: nearbyDiscovery,
      );
      addTearDown(receiverService.dispose);
      addTearDown(container.dispose);

      final notifier = container.read(driftAppNotifierProvider.notifier);
      await _flushAsyncWork(tester);

      expect(nearbyDiscovery.scanCount, 0);

      notifier.pickSendItems();
      await _flushAsyncWork(tester);
      expect(nearbyDiscovery.scanCount, 1);
      expect(
        container.read(driftAppNotifierProvider).session,
        isA<SendDraftSession>(),
      );

      notifier.resetShell();
      await _flushAsyncWork(tester);

      nearbyResults.complete([
        const SendDestinationViewData(
          name: 'Lab Mac',
          kind: SendDestinationKind.laptop,
          lanTicket: 'ticket-123',
          lanFullname: 'lab-mac._drift._udp.local.',
        ),
      ]);
      await _flushAsyncWork(tester);

      final state = container.read(driftAppNotifierProvider);
      expect(state.session, isA<IdleSession>());
      expect(state.nearbySendDestinations, isEmpty);
    },
  );

  testWidgets('nearby scan is rescheduled after append and remove', (
    tester,
  ) async {
    final receiverService = FakeReceiverServiceSource();
    final nearbyDiscovery = FakeNearbyDiscoverySource();
    final sendItemSource = FakeSendItemSource(
      pickResponses: const [
        ['sample.txt'],
        ['notes.pdf'],
      ],
    );
    final container = _buildContainer(
      receiverServiceSource: receiverService,
      nearbyDiscoverySource: nearbyDiscovery,
      sendItemSource: sendItemSource,
    );
    addTearDown(receiverService.dispose);
    addTearDown(container.dispose);

    final notifier = container.read(driftAppNotifierProvider.notifier);
    await _flushAsyncWork(tester);

    notifier.pickSendItems();
    await _flushAsyncWork(tester);
    expect(nearbyDiscovery.scanCount, 1);

    notifier.appendSendItemsFromPicker();
    await _flushAsyncWork(tester);
    expect(nearbyDiscovery.scanCount, 2);

    notifier.removeSendItem('sample.txt');
    await _flushAsyncWork(tester);
    expect(nearbyDiscovery.scanCount, 3);

    notifier.resetShell();
    await _flushAsyncWork(tester);
  });

  testWidgets('starting send requires explicit action before transfer state', (
    tester,
  ) async {
    final receiverService = FakeReceiverServiceSource();
    final sendTransferSource = FakeSendTransferSource();
    final container = _buildContainer(
      receiverServiceSource: receiverService,
      sendTransferSource: sendTransferSource,
    );
    addTearDown(sendTransferSource.dispose);
    addTearDown(receiverService.dispose);
    addTearDown(container.dispose);

    final notifier = container.read(driftAppNotifierProvider.notifier);
    await _flushAsyncWork(tester);

    notifier.pickSendItems();
    await _flushAsyncWork(tester);
    notifier.updateSendDestinationCode('ab2cd3');
    await _flushAsyncWork(tester);

    expect(sendTransferSource.lastRequest, isNull);

    notifier.startSend();
    await _flushAsyncWork(tester);

    expect(sendTransferSource.lastRequest?.code, 'AB2CD3');

    sendTransferSource.controller.add(
      _sendUpdate(phase: SendTransferUpdatePhase.connecting),
    );
    await _flushAsyncWork(tester);
    expect(
      container.read(driftAppNotifierProvider).session,
      isA<SendTransferSession>(),
    );

    sendTransferSource.controller.add(
      _sendUpdate(
        phase: SendTransferUpdatePhase.sending,
        bytesSent: 9 * 1024,
        totalBytes: 18 * 1024,
      ),
    );
    await _flushAsyncWork(tester);

    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });

    sendTransferSource.controller.add(
      _sendUpdate(
        phase: SendTransferUpdatePhase.completed,
        destinationLabel: 'Maya’s iPhone',
        statusMessage: 'Files sent successfully',
        bytesSent: 18 * 1024,
        totalBytes: 18 * 1024,
      ),
    );
    await _flushAsyncWork(tester);

    final state = container.read(driftAppNotifierProvider);
    expect(state.session, isA<SendResultSession>());
    expect((state.session as SendResultSession).success, isTrue);
    expect(
      state.sendCompletionMetrics?.map((row) => row.label),
      containsAll([
        'Sent to',
        'Files',
        'Size',
        'Transfer time',
        'Average speed',
      ]),
    );
    expect(receiverService.discoverableCalls.last, isFalse);
  });

  testWidgets(
    'incoming offers move to review and accept/decline use receiver service',
    (tester) async {
      final receiverService = FakeReceiverServiceSource();
      final container = _buildContainer(
        receiverServiceSource: receiverService,
        enableIdleIncomingListener: true,
      );
      addTearDown(receiverService.dispose);
      addTearDown(container.dispose);

      container.read(driftAppNotifierProvider.notifier);
      await _flushAsyncWork(tester);

      receiverService.incomingController.add(_incomingOfferEvent());
      await _flushAsyncWork(tester);

      expect(
        container.read(driftAppNotifierProvider).session,
        isA<ReceiveOfferSession>(),
      );

      container.read(driftAppNotifierProvider.notifier).acceptReceiveOffer();
      await _flushAsyncWork(tester);
      expect(
        container.read(driftAppNotifierProvider).session,
        isA<ReceiveTransferSession>(),
      );
      receiverService.incomingController.add(
        _incomingReceivingEvent(receivedBytes: BigInt.from(9 * 1024)),
      );
      await _flushAsyncWork(tester);
      final receivingState = container.read(driftAppNotifierProvider);
      expect(receivingState.receivePayloadBytesReceived, 9 * 1024);
      expect(receivingState.receivePayloadTotalBytes, 18 * 1024);
      expect(receiverService.respondToOfferCalls.last, isTrue);

      receiverService.incomingController.add(_incomingOfferEvent());
      await _flushAsyncWork(tester);
      container.read(driftAppNotifierProvider.notifier).declineReceiveOffer();
      await _flushAsyncWork(tester);
      expect(
        container.read(driftAppNotifierProvider).session,
        isA<IdleSession>(),
      );
      expect(receiverService.respondToOfferCalls.last, isFalse);
    },
  );
}

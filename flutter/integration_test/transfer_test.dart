import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift_app/app/drift_app.dart';
import 'package:drift_app/features/send/send_providers.dart' as send_deps;
import 'package:drift_app/state/drift_providers.dart';
import 'package:drift_app/platform/send_item_source.dart';
import 'package:drift_app/platform/send_transfer_source.dart';
import 'package:drift_app/state/nearby_discovery_source.dart';
import 'package:drift_app/state/receiver_service_source.dart';
import 'package:drift_app/core/models/transfer_models.dart';
import 'package:drift_app/state/app_identity.dart';
import 'package:drift_app/src/rust/frb_generated.dart';
import 'package:drift_app/src/rust/api/receiver.dart' as rust_receiver;

class MockSendItemSource implements SendItemSource {
  List<TransferItemViewData> items = [];
  @override
  Future<List<TransferItemViewData>> pickFiles() async => items;
  @override
  Future<List<String>> pickAdditionalPaths() async => [];
  @override
  Future<List<TransferItemViewData>> pickAdditionalFiles({
    required List<String> existingPaths,
  }) async => items;
  @override
  Future<List<TransferItemViewData>> loadPaths(List<String> paths) async =>
      items;
  @override
  Future<List<TransferItemViewData>> appendPaths({
    required List<String> existingPaths,
    required List<String> incomingPaths,
  }) async => items;
  @override
  Future<List<TransferItemViewData>> removePath({
    required List<String> existingPaths,
    required String removedPath,
  }) async => items;
}

class MockSendTransferSource implements SendTransferSource {
  final StreamController<SendTransferUpdate> _controller =
      StreamController<SendTransferUpdate>.broadcast();
  void emit(SendTransferUpdate update) => _controller.add(update);
  @override
  Stream<SendTransferUpdate> startTransfer(SendTransferRequestData request) =>
      _controller.stream;

  @override
  Future<void> cancelTransfer() async {}
}

class MockNearbyDiscoverySource implements NearbyDiscoverySource {
  List<SendDestinationViewData> destinations = [];
  @override
  Future<List<SendDestinationViewData>> scan({
    Duration timeout = const Duration(seconds: 12),
  }) async => destinations;
}

class MockReceiverServiceSource implements ReceiverServiceSource {
  final StreamController<ReceiverBadgeState> _badgeController =
      StreamController<ReceiverBadgeState>.broadcast();
  final StreamController<rust_receiver.ReceiverTransferEvent>
  _incomingController =
      StreamController<rust_receiver.ReceiverTransferEvent>.broadcast();
  void emitBadge(ReceiverBadgeState badge) => _badgeController.add(badge);
  void emitIncoming(rust_receiver.ReceiverTransferEvent event) =>
      _incomingController.add(event);
  @override
  Stream<ReceiverBadgeState> watchBadge(DriftAppIdentity identity) =>
      _badgeController.stream;
  @override
  Stream<rust_receiver.ReceiverTransferEvent> watchIncomingTransfers(
    DriftAppIdentity identity,
  ) => _incomingController.stream;
  @override
  Future<void> setDiscoverable({required bool enabled}) async {}
  @override
  Future<void> respondToOffer({required bool accept}) async {}
  @override
  Future<void> cancelTransfer() async {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await RustLib.init();
  });

  testWidgets('Full send flow', (WidgetTester tester) async {
    final mockSendItemSource = MockSendItemSource();
    final mockSendTransferSource = MockSendTransferSource();
    final mockNearbyDiscoverySource = MockNearbyDiscoverySource();
    final mockReceiverServiceSource = MockReceiverServiceSource();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sendItemSourceProvider.overrideWithValue(mockSendItemSource),
          sendTransferSourceProvider.overrideWithValue(mockSendTransferSource),
          nearbyDiscoverySourceProvider.overrideWithValue(
            mockNearbyDiscoverySource,
          ),
          receiverServiceSourceProvider.overrideWithValue(
            mockReceiverServiceSource,
          ),
          animateSendingConnectionProvider.overrideWithValue(false),
        ],
        child: const DriftApp(),
      ),
    );

    await tester.pump(const Duration(milliseconds: 500));
    mockReceiverServiceSource.emitBadge(
      const ReceiverBadgeState(
        code: 'WXYZ12',
        status: 'Ready',
        phase: ReceiverBadgePhase.ready,
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Drop files to send'), findsOneWidget);

    mockSendItemSource.items = [
      const TransferItemViewData(
        name: 'test_file.txt',
        path: '/mock/test_file.txt',
        size: '1.2 MB',
        kind: TransferItemKind.file,
        sizeBytes: 1200000,
      ),
    ];

    final notifier = ProviderScope.containerOf(
      tester.element(find.byType(DriftApp)),
    ).read(send_deps.sendControllerProvider.notifier);
    notifier.pickSendItems();

    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('test_file.txt'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(DriftApp)),
    );

    final codeField = find.byType(TextField);
    await tester.enterText(codeField, 'ABCDEF');
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('test_file.txt'), findsOneWidget);
    expect(find.text('Send with code'), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);
    expect(find.text('Connecting...'), findsNothing);
    expect(find.text('Sending...'), findsNothing);

    await tester.tap(find.text('Send'));
    await tester.pump(const Duration(milliseconds: 500));

    mockSendTransferSource.emit(
      const SendTransferUpdate(
        phase: SendTransferUpdatePhase.connecting,
        destinationLabel: 'Receiver',
        statusMessage: 'Connecting...',
        itemCount: 1,
        totalSize: '1.2 MB',
        bytesSent: 0,
        totalBytes: 1200000,
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(
      container.read(send_deps.sendStateProvider).sendStage,
      TransferStage.ready,
    );

    mockSendTransferSource.emit(
      const SendTransferUpdate(
        phase: SendTransferUpdatePhase.sending,
        destinationLabel: 'Receiver',
        statusMessage: 'Sending...',
        itemCount: 1,
        totalSize: '1.2 MB',
        bytesSent: 600000,
        totalBytes: 1200000,
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(
      container.read(send_deps.sendStateProvider).sendStage,
      TransferStage.waiting,
    );

    mockSendTransferSource.emit(
      const SendTransferUpdate(
        phase: SendTransferUpdatePhase.completed,
        destinationLabel: 'Receiver',
        statusMessage: 'Sent!',
        itemCount: 1,
        totalSize: '1.2 MB',
        bytesSent: 1200000,
        totalBytes: 1200000,
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(
      container.read(send_deps.sendStateProvider).sendStage,
      TransferStage.completed,
    );
    container
        .read(send_deps.sendControllerProvider.notifier)
        .handleTransferResultPrimaryAction();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Drop files to send'), findsOneWidget);
  });
}

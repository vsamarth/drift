import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:app/features/send/application/controller.dart';
import 'package:app/features/send/application/model.dart';
import 'package:app/features/send/application/state.dart';
import 'package:app/features/send/presentation/send_transfer_route.dart';
import 'package:app/features/send/presentation/widgets/recipient_avatar.dart';
import 'package:app/features/settings/settings_providers.dart';
import 'package:app/platform/send_transfer_source.dart';
import 'package:app/src/rust/api/transfer.dart' as rust_transfer;
import '../../../support/settings_test_overrides.dart';

class FakeSendTransferSource implements SendTransferSource {
  final StreamController<SendTransferUpdate> _updates =
      StreamController<SendTransferUpdate>.broadcast(sync: true);

  SendTransferRequestData? lastRequest;
  bool cancelCalled = false;

  @override
  Stream<SendTransferUpdate> startTransfer(SendTransferRequestData request) {
    lastRequest = request;
    return _updates.stream;
  }

  @override
  Future<void> cancelTransfer() async {
    cancelCalled = true;
  }

  void emit(SendTransferUpdate update) {
    _updates.add(update);
  }

  Future<void> close() async {
    await _updates.close();
  }
}

Future<void> _pumpRoute(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump();
}

GoRouter _buildRouter(SendRequestData request) {
  return GoRouter(
    initialLocation: '/send/transfer',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const SizedBox.shrink(),
        routes: [
          GoRoute(
            path: 'send/transfer',
            builder: (context, state) => SendTransferRoutePage(request: request),
          ),
        ],
      ),
    ],
  );
}

rust_transfer.TransferPlanData _buildPlan() {
  return rust_transfer.TransferPlanData(
    sessionId: 'session-1',
    totalFiles: 1,
    totalBytes: BigInt.from(1024),
    files: [
      rust_transfer.TransferPlanFileData(
        id: 0,
        path: '/tmp/report.pdf',
        size: BigInt.from(1024),
      ),
    ],
  );
}

rust_transfer.TransferSnapshotData _buildSnapshot({
  required rust_transfer.TransferPhaseData phase,
  required BigInt bytesTransferred,
  required BigInt? bytesPerSec,
  required BigInt? etaSeconds,
}) {
  return rust_transfer.TransferSnapshotData(
    sessionId: 'session-1',
    phase: phase,
    totalFiles: 1,
    completedFiles: phase == rust_transfer.TransferPhaseData.completed ? 1 : 0,
    totalBytes: BigInt.from(1024),
    bytesTransferred: bytesTransferred,
    activeFileId: 0,
    activeFileBytes: bytesTransferred,
    bytesPerSec: bytesPerSec,
    etaSeconds: etaSeconds,
  );
}

void main() {
  testWidgets('send transfer route shows connecting waiting accepted sending and completed states', (
    WidgetTester tester,
  ) async {
    final fakeSource = FakeSendTransferSource();
    final container = ProviderContainer(
      overrides: [
        initialAppSettingsProvider.overrideWithValue(testAppSettings),
        sendTransferSourceProvider.overrideWithValue(fakeSource),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(fakeSource.close);

    final controller = container.read(sendControllerProvider.notifier);
    controller.beginDraft([
      SendPickedFile(
        path: '/tmp/report.pdf',
        name: 'report.pdf',
        sizeBytes: BigInt.from(1024),
      ),
    ]);
    controller.updateDestinationCode('ABC123');
    final request = controller.buildSendRequest()!;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: _buildRouter(request)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    expect(container.read(sendControllerProvider), isA<SendStateTransferring>());
    expect(find.byType(RecipientAvatar).last, findsOneWidget);
    expect(find.text('CONNECTING'), findsOneWidget);
    expect(find.text('Cancel transfer'), findsOneWidget);

    fakeSource.emit(
      SendTransferUpdate(
        phase: SendTransferUpdatePhase.waitingForDecision,
        destinationLabel: 'Laptop',
        statusMessage: 'Waiting for confirmation.',
        itemCount: BigInt.one,
        totalSize: BigInt.from(1024),
        bytesSent: BigInt.zero,
        totalBytes: BigInt.from(1024),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.text('WAITING'), findsWidgets);

    fakeSource.emit(
      SendTransferUpdate(
        phase: SendTransferUpdatePhase.accepted,
        destinationLabel: 'Laptop',
        statusMessage: 'Receiver confirmed.',
        itemCount: BigInt.one,
        totalSize: BigInt.from(1024),
        bytesSent: BigInt.zero,
        totalBytes: BigInt.from(1024),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.text('ACCEPTED'), findsWidgets);

    final plan = _buildPlan();
    final snapshot = _buildSnapshot(
      phase: rust_transfer.TransferPhaseData.transferring,
      bytesTransferred: BigInt.from(512),
      bytesPerSec: BigInt.from(256),
      etaSeconds: BigInt.from(4),
    );
    fakeSource.emit(
      SendTransferUpdate(
        phase: SendTransferUpdatePhase.sending,
        destinationLabel: 'Laptop',
        statusMessage: 'Sending files.',
        itemCount: BigInt.one,
        totalSize: BigInt.from(1024),
        bytesSent: BigInt.from(512),
        totalBytes: BigInt.from(1024),
        plan: plan,
        snapshot: snapshot,
        remoteDeviceType: 'laptop',
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.textContaining('256 B/s'), findsOneWidget);
    expect(find.textContaining('4 s left'), findsOneWidget);
    expect(find.text('SENDING'), findsWidgets);

    fakeSource.emit(
      SendTransferUpdate.completed(
        destinationLabel: 'Laptop',
        statusMessage: 'Sent successfully',
        itemCount: BigInt.one,
        totalSize: BigInt.from(1024),
        bytesSent: BigInt.from(1024),
        plan: plan,
        snapshot: _buildSnapshot(
          phase: rust_transfer.TransferPhaseData.completed,
          bytesTransferred: BigInt.from(1024),
          bytesPerSec: BigInt.from(256),
          etaSeconds: BigInt.zero,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.text('SUCCESS'), findsWidgets);
    expect(find.text('Files finished transferring successfully.'), findsOneWidget);
    expect(find.text('Done'), findsWidgets);
    expect(find.byType(RecipientAvatar).last, findsOneWidget);
  });

  testWidgets('send transfer route shows declined cancelled and failed results', (
    WidgetTester tester,
  ) async {
    final fixtures = <({
      SendTransferUpdate update,
      String expectedStatusLabel,
      String expectedSubtitle,
    })>[
      (
        update: SendTransferUpdate.declined(
          destinationLabel: 'Laptop',
          statusMessage: 'Receiver declined',
          itemCount: BigInt.one,
          totalSize: BigInt.from(1024),
          bytesSent: BigInt.zero,
          totalBytes: BigInt.from(1024),
        ),
        expectedStatusLabel: 'DECLINED',
        expectedSubtitle: 'Receiver declined',
      ),
      (
        update: SendTransferUpdate.cancelled(
          destinationLabel: 'Laptop',
          statusMessage: 'Cancelled',
          itemCount: BigInt.one,
          totalSize: BigInt.from(1024),
          bytesSent: BigInt.zero,
          totalBytes: BigInt.from(1024),
        ),
        expectedStatusLabel: 'CANCELLED',
        expectedSubtitle: 'Cancelled',
      ),
      (
        update: SendTransferUpdate.failed(
          destinationLabel: 'Laptop',
          statusMessage: 'Failed',
          itemCount: BigInt.one,
          totalSize: BigInt.from(1024),
          bytesSent: BigInt.zero,
          totalBytes: BigInt.from(1024),
          error: const SendTransferErrorData(
            kind: SendTransferErrorKind.internal,
            title: 'Send failed',
            message: 'boom',
            retryable: false,
          ),
        ),
        expectedStatusLabel: 'FAILED',
        expectedSubtitle: 'boom',
      ),
    ];

    for (final fixture in fixtures) {
      final fakeSource = FakeSendTransferSource();
      final container = ProviderContainer(
        overrides: [
          initialAppSettingsProvider.overrideWithValue(testAppSettings),
          sendTransferSourceProvider.overrideWithValue(fakeSource),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(fakeSource.close);

      final controller = container.read(sendControllerProvider.notifier);
      controller.beginDraft([
        SendPickedFile(
          path: '/tmp/report.pdf',
          name: 'report.pdf',
          sizeBytes: BigInt.from(1024),
        ),
      ]);
      controller.updateDestinationCode('ABC123');
      final request = controller.buildSendRequest()!;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: _buildRouter(request)),
        ),
      );
      await _pumpRoute(tester);

      fakeSource.emit(fixture.update);
      await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
      expect(find.text(fixture.expectedStatusLabel), findsOneWidget);
      expect(find.text(fixture.expectedSubtitle), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(find.byType(RecipientAvatar).last, findsOneWidget);
    }
  });
}

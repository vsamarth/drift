import 'package:drift_app/core/models/transfer_models.dart';
import 'package:drift_app/features/receive/receive_providers.dart';
import 'package:drift_app/features/receive/widgets/receive_receiving_card.dart';
import 'package:drift_app/features/receive/widgets/receive_review_card.dart';
import 'package:drift_app/platform/storage_access_source.dart';
import 'package:drift_app/state/app_identity.dart';
import 'package:drift_app/state/drift_app_state.dart';
import 'package:drift_app/state/drift_app_notifier.dart';
import 'package:drift_app/state/drift_dependencies.dart';
import 'package:drift_app/state/receiver_service_source.dart';
import 'package:drift_app/state/settings_store.dart';
import 'package:drift_app/state/drift_providers.dart';
import 'package:drift_app/src/rust/api/receiver.dart' as rust_receiver;
import 'package:drift_app/src/rust/api/transfer.dart' as rust_transfer;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeReceiverServiceSource implements ReceiverServiceSource {
  const _FakeReceiverServiceSource();

  @override
  Stream<ReceiverBadgeState> watchBadge(DriftAppIdentity identity) {
    return const Stream<ReceiverBadgeState>.empty();
  }

  @override
  Stream<rust_receiver.ReceiverTransferEvent> watchIncomingTransfers(
    DriftAppIdentity identity,
  ) {
    return const Stream<rust_receiver.ReceiverTransferEvent>.empty();
  }

  @override
  Future<void> cancelTransfer() async {}

  @override
  Future<void> respondToOffer({required bool accept}) async {}

  @override
  Future<void> setDiscoverable({required bool enabled}) async {}
}

class _FakeAppNotifier extends DriftAppNotifier {
  _FakeAppNotifier(this._state);

  final DriftAppState _state;
  int acceptCalls = 0;
  int declineCalls = 0;
  int cancelCalls = 0;

  @override
  DriftAppState build() {
    return _state;
  }

  void acceptReceiveOffer() {
    acceptCalls += 1;
  }

  void declineReceiveOffer() {
    declineCalls += 1;
  }

  void cancelReceiveInProgress() {
    cancelCalls += 1;
  }
}

ProviderScope _buildScope({
  required _FakeAppNotifier notifier,
  required Widget child,
}) {
  return ProviderScope(
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
      storageAccessSourceProvider.overrideWith(
        (ref) => const StorageAccessSource(),
      ),
      animateSendingConnectionProvider.overrideWith((ref) => false),
      receiverServiceSourceProvider.overrideWith(
        (ref) => const _FakeReceiverServiceSource(),
      ),
      driftAppNotifierProvider.overrideWith(() => notifier),
    ],
    child: child,
  );
}

void main() {
  testWidgets('receive review card renders from receive state and delegates', (
    tester,
  ) async {
    final notifier = _FakeAppNotifier(
      DriftAppState(
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
        session: ReceiveOfferSession(
          items: const [
            TransferItemViewData(
              name: 'report.pdf',
              path: 'report.pdf',
              size: '2 KB',
              kind: TransferItemKind.file,
              sizeBytes: 2048,
            ),
          ],
          summary: const TransferSummaryViewData(
            itemCount: 1,
            totalSize: '2 KB',
            code: 'F9P2Q1',
            expiresAt: '',
            destinationLabel: 'Downloads',
            statusMessage: 'Incoming transfer',
            senderName: 'Sam',
          ),
          decisionPending: true,
          payloadTotalBytes: 2048,
          senderDeviceType: 'phone',
        ),
        animateSendingConnection: false,
      ),
    );

    await tester.pumpWidget(
      _buildScope(
        notifier: notifier,
        child: const MaterialApp(home: Scaffold(body: ReceiveReviewCard())),
      ),
    );

    expect(find.text('Save to Downloads'), findsOneWidget);

    await tester.tap(find.text('Save to Downloads'));
    await tester.pump();
    await tester.tap(find.text('Decline'));
    await tester.pump();

    expect(notifier.acceptCalls, 1);
    expect(notifier.declineCalls, 1);
  });

  testWidgets('receive receiving card renders and cancels through the bridge', (
    tester,
  ) async {
    final notifier = _FakeAppNotifier(
      DriftAppState(
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
        session: ReceiveTransferSession(
          items: const [
            TransferItemViewData(
              name: 'report.pdf',
              path: 'report.pdf',
              size: '2 KB',
              kind: TransferItemKind.file,
              sizeBytes: 2048,
            ),
          ],
          summary: const TransferSummaryViewData(
            itemCount: 1,
            totalSize: '2 KB',
            code: 'F9P2Q1',
            expiresAt: '',
            destinationLabel: 'Downloads',
            statusMessage: 'Receiving files...',
            senderName: 'Sam',
          ),
          payloadBytesReceived: 1024,
          payloadTotalBytes: 2048,
          payloadSpeedLabel: '1 MB/s',
          payloadEtaLabel: '1 min',
          senderDeviceType: 'phone',
        ),
        animateSendingConnection: false,
      ),
    );

    await tester.pumpWidget(
      _buildScope(
        notifier: notifier,
        child: const MaterialApp(home: Scaffold(body: ReceiveReceivingCard())),
      ),
    );

    expect(find.text('Receiving files...'), findsOneWidget);
    expect(find.text('1 MB/s • 1 min'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes, cancel'));
    await tester.pump();

    expect(notifier.cancelCalls, 1);
  });
}

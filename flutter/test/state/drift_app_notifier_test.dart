import 'dart:async';

import 'package:drift_app/state/app_identity.dart';
import 'package:drift_app/state/drift_app_state.dart';
import 'package:drift_app/state/drift_providers.dart';
import 'package:drift_app/state/receiver_service_source.dart';
import 'package:drift_app/state/settings_store.dart';
import 'package:drift_app/src/rust/api/error.dart' as rust_error;
import 'package:drift_app/src/rust/api/receiver.dart' as rust_receiver;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _flushAsyncWork(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

ProviderContainer _buildContainer({
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

class FakeReceiverServiceSource implements ReceiverServiceSource {
  FakeReceiverServiceSource({
    this.initialBadge = const ReceiverBadgeState(
      code: 'F9P2Q1',
      status: 'Ready',
      phase: ReceiverBadgePhase.ready,
    ),
    this.respondError,
    this.cancelError,
  });

  final ReceiverBadgeState initialBadge;
  final Object? respondError;
  final Object? cancelError;
  final List<bool> discoverableCalls = <bool>[];
  final List<bool> respondToOfferCalls = <bool>[];
  final StreamController<ReceiverBadgeState> badgeController =
      StreamController<ReceiverBadgeState>.broadcast();
  final StreamController<rust_receiver.ReceiverTransferEvent>
  incomingController =
      StreamController<rust_receiver.ReceiverTransferEvent>.broadcast();

  @override
  Future<void> respondToOffer({required bool accept}) async {
    if (respondError != null) {
      throw respondError!;
    }
    respondToOfferCalls.add(accept);
  }

  @override
  Future<void> cancelTransfer() async {
    if (cancelError != null) {
      throw cancelError!;
    }
  }

  @override
  Future<void> setDiscoverable({required bool enabled}) async {
    discoverableCalls.add(enabled);
  }

  @override
  Stream<ReceiverBadgeState> watchBadge(DriftAppIdentity identity) {
    return badgeController.stream;
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
    error: const rust_error.UserFacingErrorData(
      kind: rust_error.UserFacingErrorKindData.connectionLost,
      title: 'Connection lost',
      message: 'Drift lost the connection while receiving files.',
      recovery: 'Try again when both devices are connected.',
      retryable: true,
    ),
  );
}

rust_receiver.ReceiverTransferEvent _incomingFailedEvent({
  required BigInt receivedBytes,
}) {
  return rust_receiver.ReceiverTransferEvent(
    phase: rust_receiver.ReceiverTransferPhase.failed,
    senderName: 'Maya',
    senderDeviceType: 'phone',
    destinationLabel: 'Downloads',
    saveRootLabel: 'Downloads',
    statusMessage: 'Transfer failed.',
    itemCount: BigInt.one,
    totalSizeBytes: BigInt.from(18 * 1024),
    bytesReceived: receivedBytes,
    totalSizeLabel: '18 KB',
    files: const [],
    error: const rust_error.UserFacingErrorData(
      kind: rust_error.UserFacingErrorKindData.connectionLost,
      title: 'Connection lost',
      message: 'Drift lost the connection while receiving files.',
      recovery: 'Try again when both devices are connected.',
      retryable: true,
    ),
  );
}

rust_receiver.ReceiverTransferEvent _incomingDeclinedEvent() {
  return rust_receiver.ReceiverTransferEvent(
    phase: rust_receiver.ReceiverTransferPhase.declined,
    senderName: 'Maya',
    senderDeviceType: 'phone',
    destinationLabel: 'Downloads',
    saveRootLabel: 'Downloads',
    statusMessage: 'Transfer declined.',
    itemCount: BigInt.one,
    totalSizeBytes: BigInt.from(18 * 1024),
    bytesReceived: BigInt.zero,
    totalSizeLabel: '18 KB',
    files: const [],
  );
}

void main() {
  // Receive-flow coverage will peel into feature-specific tests as the rewrite progresses.
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
      receiverService.incomingController.add(_incomingDeclinedEvent());
      await _flushAsyncWork(tester);
      expect(
        container.read(driftAppNotifierProvider).session,
        isA<ReceiveResultSession>(),
      );
      expect(receiverService.respondToOfferCalls.last, isFalse);
    },
  );

  testWidgets('incoming receive failure stays on a terminal error state', (
    tester,
  ) async {
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
    container.read(driftAppNotifierProvider.notifier).acceptReceiveOffer();
    await _flushAsyncWork(tester);

    receiverService.incomingController.add(
      _incomingReceivingEvent(receivedBytes: BigInt.from(9 * 1024)),
    );
    await _flushAsyncWork(tester);

    receiverService.incomingController.add(
      _incomingFailedEvent(receivedBytes: BigInt.from(9 * 1024)),
    );
    await _flushAsyncWork(tester);

    final state = container.read(driftAppNotifierProvider);
    expect(state.session, isA<ReceiveResultSession>());
    expect(state.transferResult?.outcome, TransferResultOutcomeData.failed);
    expect(
      state.transferResult?.message,
      'Drift lost the connection while receiving files.',
    );
    expect(state.receivePayloadBytesReceived, 9 * 1024);
  });

  testWidgets('incoming declined stays on a terminal declined state', (
    tester,
  ) async {
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
    receiverService.incomingController.add(_incomingDeclinedEvent());
    await _flushAsyncWork(tester);

    final state = container.read(driftAppNotifierProvider);
    expect(state.session, isA<ReceiveResultSession>());
    expect(state.transferResult?.outcome, TransferResultOutcomeData.declined);
    expect(state.transferResult?.title, 'Transfer declined');
  });

  testWidgets('respond to offer failure stays visible as a receive error', (
    tester,
  ) async {
    final receiverService = FakeReceiverServiceSource(
      respondError: Exception('backend unavailable'),
    );
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
    container.read(driftAppNotifierProvider.notifier).acceptReceiveOffer();
    await _flushAsyncWork(tester);

    final state = container.read(driftAppNotifierProvider);
    expect(state.session, isA<ReceiveResultSession>());
    expect(state.transferResult?.outcome, TransferResultOutcomeData.failed);
    expect(
      state.transferResult?.message,
      'Drift couldn\'t accept the transfer.',
    );
  });

  testWidgets('receive cancel failure stays visible as a receive error', (
    tester,
  ) async {
    final receiverService = FakeReceiverServiceSource(
      cancelError: Exception('cancel failed'),
    );
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
    container.read(driftAppNotifierProvider.notifier).acceptReceiveOffer();
    await _flushAsyncWork(tester);
    receiverService.incomingController.add(
      _incomingReceivingEvent(receivedBytes: BigInt.from(9 * 1024)),
    );
    await _flushAsyncWork(tester);

    container.read(driftAppNotifierProvider.notifier).cancelReceiveInProgress();
    await _flushAsyncWork(tester);

    final state = container.read(driftAppNotifierProvider);
    expect(state.session, isA<ReceiveResultSession>());
    expect(state.transferResult?.outcome, TransferResultOutcomeData.failed);
    expect(
      state.transferResult?.message,
      'Drift couldn\'t cancel the transfer.',
    );
  });
}

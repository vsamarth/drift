import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/receive/application/state.dart';
import 'package:app/features/send/application/controller.dart';
import 'package:app/features/send/application/model.dart';
import 'package:app/features/send/application/state.dart';
import 'package:app/features/send/application/transfer_state.dart';
import 'package:app/features/settings/settings_providers.dart';
import 'package:app/platform/send_transfer_source.dart';
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

void main() {
  test('send controller starts idle', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final state = container.read(sendControllerProvider);

    expect(state.phase, SendSessionPhase.idle);
    expect(state.destination.mode, SendDestinationMode.none);
    expect(state.request, isNull);
  });

  test('send controller can begin and clear a draft', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = container.read(sendControllerProvider.notifier);
    controller.beginDraft([
      SendPickedFile(
        path: '/tmp/report.pdf',
        name: 'report.pdf',
        sizeBytes: BigInt.from(1024),
      ),
    ]);

    final drafting = container.read(sendControllerProvider);
    expect(drafting.phase, SendSessionPhase.drafting);
    expect(drafting.items, hasLength(1));
    expect(drafting.destination.mode, SendDestinationMode.none);

    controller.clearDraft();

    final idle = container.read(sendControllerProvider);
    expect(idle.phase, SendSessionPhase.idle);
    expect(idle.items, isEmpty);
    expect(idle.destination.mode, SendDestinationMode.none);
  });

  test('send controller buildSendRequest returns null when destination is missing', () {
    final container = ProviderContainer(
      overrides: [
        initialAppSettingsProvider.overrideWithValue(testAppSettings),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sendControllerProvider.notifier);
    controller.beginDraft([
      SendPickedFile(
        path: '/tmp/report.pdf',
        name: 'report.pdf',
        sizeBytes: BigInt.from(1024),
      ),
    ]);

    expect(controller.buildSendRequest(), isNull);
    expect(controller.canStartSend(), isFalse);
  });

  test('send controller builds a code request for a valid 6-character code', () {
    final container = ProviderContainer(
      overrides: [
        initialAppSettingsProvider.overrideWithValue(testAppSettings),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sendControllerProvider.notifier);
    controller.beginDraft([
      SendPickedFile(
        path: '/tmp/report.pdf',
        name: 'report.pdf',
        sizeBytes: BigInt.from(1024),
      ),
    ]);
    controller.updateDestinationCode('ABC123');

    final request = controller.buildSendRequest();
    expect(request, isNotNull);
    expect(controller.canStartSend(), isTrue);
    expect(request?.destinationMode, SendDestinationMode.code);
    expect(request?.code, 'ABC123');
    expect(request?.ticket, isNull);
    expect(request?.lanDestinationLabel, isNull);
    expect(request?.paths, ['/tmp/report.pdf']);
    expect(request?.deviceName, 'Drift');
    expect(request?.serverUrl, isNull);
  });

  test('send controller buildSendRequest returns null for an invalid code', () {
    final container = ProviderContainer(
      overrides: [
        initialAppSettingsProvider.overrideWithValue(testAppSettings),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sendControllerProvider.notifier);
    controller.beginDraft([
      SendPickedFile(
        path: '/tmp/report.pdf',
        name: 'report.pdf',
        sizeBytes: BigInt.from(1024),
      ),
    ]);
    controller.updateDestinationCode('ABC');

    expect(controller.buildSendRequest(), isNull);
    expect(controller.canStartSend(), isFalse);
  });

  test('send controller builds a nearby request from the selected receiver', () {
    final container = ProviderContainer(
      overrides: [
        initialAppSettingsProvider.overrideWithValue(testAppSettings),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sendControllerProvider.notifier);
    controller.beginDraft([
      SendPickedFile(
        path: '/tmp/report.pdf',
        name: 'report.pdf',
        sizeBytes: BigInt.from(1024),
      ),
    ]);
    controller.selectNearbyReceiver(
      const NearbyReceiver(
        fullname: 'samarth-laptop',
        label: 'Laptop',
        code: 'ABC123',
        ticket: 'ticket-1',
      ),
    );

    final state = container.read(sendControllerProvider);
    expect(state.destination.mode, SendDestinationMode.nearby);
    expect(state.destination.code, isNull);

    final request = controller.buildSendRequest();
    expect(request, isNotNull);
    expect(controller.canStartSend(), isTrue);
    expect(request?.destinationMode, SendDestinationMode.nearby);
    expect(request?.ticket, 'ticket-1');
    expect(request?.lanDestinationLabel, 'Laptop');
    expect(request?.code, isNull);
    expect(request?.paths, ['/tmp/report.pdf']);
  });

  test('send controller starts transfer only for the currently validated request', () {
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
    final staleRequest = SendRequestData(
      destinationMode: SendDestinationMode.code,
      paths: request.paths,
      deviceName: request.deviceName,
      deviceType: request.deviceType,
      code: 'ZZZ999',
      serverUrl: request.serverUrl,
    );

    controller.startTransfer(staleRequest);
    expect(container.read(sendControllerProvider).phase, SendSessionPhase.drafting);
    expect(fakeSource.lastRequest, isNull);

    controller.startTransfer(request);
    expect(container.read(sendControllerProvider).phase, SendSessionPhase.transferring);
    expect(fakeSource.lastRequest?.code, 'ABC123');
    expect(
      container.read(sendControllerProvider).transfer?.phase,
      SendTransferPhase.connecting,
    );

    fakeSource.emit(
      SendTransferUpdate.completed(
        destinationLabel: 'Laptop',
        statusMessage: 'Sent successfully',
        itemCount: BigInt.one,
        totalSize: BigInt.from(1024),
        bytesSent: BigInt.from(1024),
      ),
    );
    expect(container.read(sendControllerProvider).phase, SendSessionPhase.result);
    expect(container.read(sendControllerProvider).request?.code, 'ABC123');
    expect(
      container.read(sendControllerProvider).transfer?.phase,
      SendTransferPhase.completed,
    );
  });

  test('send controller preserves progress phases from transfer updates', () {
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
    controller.startTransfer(controller.buildSendRequest()!);

    expect(
      container.read(sendControllerProvider).transfer?.phase,
      SendTransferPhase.connecting,
    );

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
    expect(
      container.read(sendControllerProvider).transfer?.phase,
      SendTransferPhase.waitingForDecision,
    );

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
    expect(
      container.read(sendControllerProvider).transfer?.phase,
      SendTransferPhase.accepted,
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
        remoteDeviceType: 'laptop',
      ),
    );
    final state = container.read(sendControllerProvider);
    expect(state.transfer?.phase, SendTransferPhase.sending);
    expect(state.transfer?.bytesSent, BigInt.from(512));
    expect(state.transfer?.remoteDeviceType, 'laptop');
  });

  test('send controller maps terminal transfer updates into result state', () {
    final fixtures = <({
      SendTransferUpdate update,
      SendTransferOutcome outcome,
      String title,
    })>[
      (
        update: SendTransferUpdate.completed(
          destinationLabel: 'Laptop',
          statusMessage: 'Sent successfully',
          itemCount: BigInt.one,
          totalSize: BigInt.from(1024),
          bytesSent: BigInt.from(1024),
        ),
        outcome: SendTransferOutcome.success,
        title: 'Sent',
      ),
      (
        update: SendTransferUpdate.declined(
          destinationLabel: 'Laptop',
          statusMessage: 'Receiver declined',
          itemCount: BigInt.one,
          totalSize: BigInt.from(1024),
          bytesSent: BigInt.zero,
          totalBytes: BigInt.from(1024),
        ),
        outcome: SendTransferOutcome.declined,
        title: 'Declined',
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
        outcome: SendTransferOutcome.cancelled,
        title: 'Cancelled',
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
        outcome: SendTransferOutcome.failed,
        title: 'Send failed',
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
      controller.startTransfer(controller.buildSendRequest()!);

      fakeSource.emit(fixture.update);
      final state = container.read(sendControllerProvider);
      expect(state.phase, SendSessionPhase.result);
      expect(state.transfer?.phase, fixture.update.phase == SendTransferUpdatePhase.completed
          ? SendTransferPhase.completed
          : fixture.update.phase == SendTransferUpdatePhase.declined
              ? SendTransferPhase.declined
              : fixture.update.phase == SendTransferUpdatePhase.cancelled
                  ? SendTransferPhase.cancelled
                  : SendTransferPhase.failed);
      expect(state.result?.outcome, fixture.outcome);
      expect(state.result?.title, fixture.title);
    }
  });

  test('send controller cancelTransfer restores drafting and cancels source', () async {
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
    controller.startTransfer(request);
    expect(container.read(sendControllerProvider).phase, SendSessionPhase.transferring);

    controller.cancelTransfer();
    await Future<void>.delayed(Duration.zero);

    expect(fakeSource.cancelCalled, isTrue);
    expect(container.read(sendControllerProvider).phase, SendSessionPhase.drafting);
    expect(container.read(sendControllerProvider).request, isNull);
  });
}

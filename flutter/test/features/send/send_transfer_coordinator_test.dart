import 'dart:async';

import 'package:drift_app/core/models/transfer_models.dart';
import 'package:drift_app/features/send/send_transfer_coordinator.dart';
import 'package:drift_app/platform/send_transfer_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('startSendTransfer builds the request and forwards updates', () async {
    final host = FakeSendTransferHost(
      items: const [
        TransferItemViewData(
          name: 'sample.txt',
          path: 'sample.txt',
          size: '18 KB',
          kind: TransferItemKind.file,
        ),
      ],
    );
    final source = FakeSendTransferSource();
    final coordinator = SendTransferCoordinator(transferSource: source);
    final updates = <SendTransferUpdate>[];

    coordinator.startSendTransfer(
      host: host,
      normalizedCode: 'AB2CD3',
      onUpdate: updates.add,
    );

    expect(host.clearNearbyScanTimerCalls, 1);
    expect(host.clearSendMetricStateCalls, 1);
    expect(source.lastRequest?.code, 'AB2CD3');
    expect(source.lastRequest?.paths, ['sample.txt']);
    expect(source.lastRequest?.deviceName, 'Drift Device');
    expect(source.lastRequest?.deviceType, 'laptop');

    source.controller.add(
      const SendTransferUpdate(
        phase: SendTransferUpdatePhase.connecting,
        destinationLabel: 'Maya\'s iPhone',
        statusMessage: 'Connecting...',
        itemCount: 1,
        totalSize: '18 KB',
        bytesSent: 0,
        totalBytes: 18 * 1024,
      ),
    );
    await pumpEventQueue();

    expect(updates, hasLength(1));
    expect(updates.single.phase, SendTransferUpdatePhase.connecting);
  });

  test('starting a second transfer cancels stale updates', () async {
    final host = FakeSendTransferHost(
      items: const [
        TransferItemViewData(
          name: 'sample.txt',
          path: 'sample.txt',
          size: '18 KB',
          kind: TransferItemKind.file,
        ),
      ],
    );
    final source = FakeSendTransferSource();
    final coordinator = SendTransferCoordinator(transferSource: source);
    final updates = <SendTransferUpdate>[];

    coordinator.startSendTransfer(
      host: host,
      normalizedCode: 'AAAAAA',
      onUpdate: updates.add,
    );
    coordinator.startSendTransfer(
      host: host,
      normalizedCode: 'BBBBBB',
      onUpdate: updates.add,
    );

    source.controller.add(
      const SendTransferUpdate(
        phase: SendTransferUpdatePhase.connecting,
        destinationLabel: 'Old device',
        statusMessage: 'Connecting...',
        itemCount: 1,
        totalSize: '18 KB',
        bytesSent: 0,
        totalBytes: 18 * 1024,
      ),
    );
    await pumpEventQueue();

    expect(updates, hasLength(1));
    expect(updates.single.destinationLabel, 'Old device');
    expect(source.lastRequest?.code, 'BBBBBB');
  });
}

Future<void> pumpEventQueue() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class FakeSendTransferHost implements SendTransferHost {
  FakeSendTransferHost({required this.items});

  final List<TransferItemViewData> items;

  final String deviceName = 'Drift Device';

  final String deviceType = 'laptop';

  final String? serverUrl = 'https://example.invalid';

  int clearNearbyScanTimerCalls = 0;
  int clearSendMetricStateCalls = 0;

  @override
  List<TransferItemViewData> get currentSendItems => items;

  @override
  String get currentDeviceName => deviceName;

  @override
  String get currentDeviceType => deviceType;

  @override
  String? get currentServerUrl => serverUrl;

  @override
  void clearNearbyScanTimer() {
    clearNearbyScanTimerCalls += 1;
  }

  @override
  void clearSendMetricState() {
    clearSendMetricStateCalls += 1;
  }

  @override
  void logSendTransferFailure(Object error, StackTrace stackTrace) {}
}

class FakeSendTransferSource implements SendTransferSource {
  final StreamController<SendTransferUpdate> controller =
      StreamController<SendTransferUpdate>.broadcast();
  SendTransferRequestData? lastRequest;

  @override
  Stream<SendTransferUpdate> startTransfer(SendTransferRequestData request) {
    lastRequest = request;
    return controller.stream;
  }

  @override
  Future<void> cancelTransfer() async {}
}

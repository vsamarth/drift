import 'dart:async';

import 'package:app/platform/rust/receiver/rust_source.dart';
import 'package:app/src/rust/api/receiver.dart' as rust_receiver;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  rust_receiver.ReceiverTransferEvent transferEvent(String statusMessage) {
    return rust_receiver.ReceiverTransferEvent(
      phase: rust_receiver.ReceiverTransferPhase.receiving,
      senderName: 'Sender',
      senderDeviceType: 'laptop',
      destinationLabel: 'This Device',
      saveRootLabel: 'Downloads',
      statusMessage: statusMessage,
      itemCount: BigInt.one,
      totalSizeBytes: BigInt.from(1024),
      bytesReceived: BigInt.from(256),
      totalSizeLabel: '1 KB',
      files: const [],
    );
  }

  test(
    'updateIdentity restarts active receiver streams with new config',
    () async {
      final pairingDeviceNames = <String>[];
      final transferDeviceNames = <String>[];
      final pairingControllers =
          <StreamController<rust_receiver.ReceiverPairingState>>[];
      final transferControllers =
          <StreamController<rust_receiver.ReceiverTransferEvent>>[];

      final source = RustReceiverServiceSource(
        deviceName: 'Old Device',
        downloadRoot: '/tmp/Drift',
        serverUrl: 'http://127.0.0.1:8787',
        pairingStreamFactory:
            ({
              serverUrl,
              required downloadRoot,
              required deviceName,
              required deviceType,
            }) {
              pairingDeviceNames.add(deviceName);
              final controller =
                  StreamController<
                    rust_receiver.ReceiverPairingState
                  >.broadcast(sync: true);
              pairingControllers.add(controller);
              return controller.stream;
            },
        transferStreamFactory:
            ({
              serverUrl,
              required downloadRoot,
              required deviceName,
              required deviceType,
            }) {
              transferDeviceNames.add(deviceName);
              final controller =
                  StreamController<
                    rust_receiver.ReceiverTransferEvent
                  >.broadcast(sync: true);
              transferControllers.add(controller);
              return controller.stream;
            },
      );

      final pairingSubscription = source.watchState().listen((_) {});
      final transferSubscription = source.watchIncomingTransfers().listen(
        (_) {},
      );
      addTearDown(() async {
        await pairingSubscription.cancel();
        await transferSubscription.cancel();
        for (final controller in pairingControllers) {
          await controller.close();
        }
        for (final controller in transferControllers) {
          await controller.close();
        }
      });

      await Future<void>.delayed(Duration.zero);

      expect(pairingDeviceNames, ['Old Device']);
      expect(transferDeviceNames, ['Old Device']);

      await source.updateIdentity(
        deviceName: 'New Device',
        downloadRoot: '/Users/maya/Downloads/Drift',
        serverUrl: 'http://127.0.0.1:8787',
      );

      await Future<void>.delayed(Duration.zero);

      expect(pairingDeviceNames, ['Old Device', 'New Device']);
      expect(transferDeviceNames, ['Old Device', 'New Device']);
    },
  );

  test(
    'updateIdentity ignores stale transfer events when only transfer stream is active',
    () async {
      final transferControllers =
          <StreamController<rust_receiver.ReceiverTransferEvent>>[];
      final seenStatuses = <String>[];
      final logs = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) {
          logs.add(message);
        }
      };
      addTearDown(() {
        debugPrint = originalDebugPrint;
      });

      final source = RustReceiverServiceSource(
        deviceName: 'Old Device',
        downloadRoot: '/tmp/Drift',
        serverUrl: 'http://127.0.0.1:8787',
        pairingStreamFactory:
            ({
              serverUrl,
              required downloadRoot,
              required deviceName,
              required deviceType,
            }) => const Stream<rust_receiver.ReceiverPairingState>.empty(),
        transferStreamFactory:
            ({
              serverUrl,
              required downloadRoot,
              required deviceName,
              required deviceType,
            }) {
              final isFirstController = transferControllers.isEmpty;
              final controller =
                  StreamController<
                    rust_receiver.ReceiverTransferEvent
                  >.broadcast(
                    sync: true,
                    onCancel: () async {
                      if (isFirstController) {
                        await Future<void>.delayed(
                          const Duration(milliseconds: 50),
                        );
                      }
                    },
                  );
              transferControllers.add(controller);
              return controller.stream;
            },
      );

      final transferSubscription = source.watchIncomingTransfers().listen((
        event,
      ) {
        seenStatuses.add(event.statusMessage);
      });
      addTearDown(() async {
        await transferSubscription.cancel();
        for (final controller in transferControllers) {
          await controller.close();
        }
      });

      await Future<void>.delayed(Duration.zero);
      expect(transferControllers, hasLength(1));

      await source.updateIdentity(
        deviceName: 'New Device',
        downloadRoot: '/Users/maya/Downloads/Drift',
        serverUrl: 'http://127.0.0.1:8787',
      );
      await Future<void>.delayed(Duration.zero);
      expect(transferControllers, hasLength(2));
      expect(
        logs.where(
          (line) => line.contains('transfer stream generation=1 start'),
        ),
        hasLength(1),
      );

      transferControllers[0].add(transferEvent('stale-old-stream'));
      transferControllers[1].add(transferEvent('fresh-new-stream'));
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(seenStatuses, ['fresh-new-stream']);
    },
  );
}

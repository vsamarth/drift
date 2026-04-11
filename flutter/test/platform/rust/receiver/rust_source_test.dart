import 'dart:async';

import 'package:app/platform/rust/receiver/rust_source.dart';
import 'package:app/src/rust/api/receiver.dart' as rust_receiver;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('updateIdentity restarts active receiver streams with new config', () async {
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
      pairingStreamFactory: ({
        serverUrl,
        required downloadRoot,
        required deviceName,
        required deviceType,
      }) {
        pairingDeviceNames.add(deviceName);
        final controller =
            StreamController<rust_receiver.ReceiverPairingState>.broadcast(
          sync: true,
        );
        pairingControllers.add(controller);
        return controller.stream;
      },
      transferStreamFactory: ({
        serverUrl,
        required downloadRoot,
        required deviceName,
        required deviceType,
      }) {
        transferDeviceNames.add(deviceName);
        final controller =
            StreamController<rust_receiver.ReceiverTransferEvent>.broadcast(
          sync: true,
        );
        transferControllers.add(controller);
        return controller.stream;
      },
    );

    final pairingSubscription = source.watchState().listen((_) {});
    final transferSubscription = source.watchIncomingTransfers().listen((_) {});
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
  });
}

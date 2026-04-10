import 'package:drift_app/core/models/transfer_models.dart';
import 'package:drift_app/features/send/send_controller.dart';
import 'package:drift_app/features/send/send_providers.dart' as send_deps;
import 'package:drift_app/features/send/send_state.dart';
import 'package:drift_app/platform/send_transfer_source.dart';
import 'package:drift_app/state/drift_app_state.dart';
import 'package:drift_app/state/drift_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'send_test_support.dart';

ProviderContainer _buildContainer({
  required FakeSendAppNotifier notifier,
  required FakeSendItemSource itemSource,
  required FakeSendTransferSource transferSource,
  required FakeNearbyDiscoverySource nearbySource,
}) {
  return ProviderContainer(
    overrides: [
      driftAppNotifierProvider.overrideWith(() => notifier),
      send_deps.sendItemSourceProvider.overrideWithValue(itemSource),
      send_deps.sendTransferSourceProvider.overrideWithValue(transferSource),
      send_deps.nearbyDiscoverySourceProvider.overrideWithValue(nearbySource),
    ],
  );
}

Future<void> _settle() async {
  await Future<void>.delayed(Duration.zero);
}

void main() {
  test('send controller wires the send helpers and sources', () async {
    final itemSource = FakeSendItemSource(
      pickResponses: [
        ['sample.txt'],
        ['sample.txt', 'notes.pdf'],
      ],
    );
    final transferSource = FakeSendTransferSource();
    final nearbySource = FakeNearbyDiscoverySource(
      destinations: const [
        SendDestinationViewData(
          name: 'Lab Mac',
          kind: SendDestinationKind.laptop,
          lanTicket: 'ticket-123',
          lanFullname: 'lab-mac._drift._udp.local.',
        ),
      ],
    );
    final notifier = FakeSendAppNotifier(buildSendDraftState());
    final container = _buildContainer(
      notifier: notifier,
      itemSource: itemSource,
      transferSource: transferSource,
      nearbySource: nearbySource,
    );
    addTearDown(() async {
      await transferSource.dispose();
      container.dispose();
    });

    SendState readState() => container.read(send_deps.sendStateProvider);

    void call(void Function(SendController controller) action) {
      action(container.read(send_deps.sendControllerProvider.notifier));
    }

    call((controller) => controller.pickSendItems());
    await _settle();
    expect(itemSource.pickFilesCalls, 1);
    expect(readState().sendItems, hasLength(1));
    expect(readState().sendItems.single.path, 'sample.txt');

    call((controller) => controller.appendSendItemsFromPicker());
    await _settle();
    expect(itemSource.pickAdditionalPathsCalls, 1);
    expect(itemSource.appendPathsCalls, 1);
    expect(
      readState().sendItems.map((item) => item.path).toList(),
      ['sample.txt', 'notes.pdf'],
    );

    call((controller) => controller.rescanNearbySendDestinations());
    await _settle();
    expect(nearbySource.scanCount, greaterThanOrEqualTo(1));
    expect(readState().nearbySendDestinations, hasLength(1));
    expect(readState().nearbyScanInProgress, isFalse);

    call((controller) => controller.updateSendDestinationCode('ab2cd3'));
    expect(readState().sendDestinationCode, 'AB2CD3');
    call((controller) => controller.clearSendDestinationCode());
    expect(readState().sendDestinationCode, '');

    call(
      (controller) => controller.selectNearbyDestination(
        readState().nearbySendDestinations.first,
      ),
    );
    expect(readState().selectedSendDestination?.name, 'Lab Mac');

    call((controller) => controller.startSend());
    expect(transferSource.startTransferCalls, 1);
    expect(transferSource.lastRequest?.ticket, 'ticket-123');
    expect(transferSource.lastRequest?.lanDestinationLabel, 'Lab Mac');
    expect(transferSource.lastRequest?.paths, ['sample.txt', 'notes.pdf']);

    transferSource.controller.add(
      const SendTransferUpdate(
        phase: SendTransferUpdatePhase.connecting,
        destinationLabel: 'Lab Mac',
        statusMessage: 'Connecting...',
        itemCount: 2,
        totalSize: '30 KB',
        bytesSent: 0,
        totalBytes: 30 * 1024,
      ),
    );
    await _settle();
    expect(readState().session, isA<SendTransferSession>());

    call((controller) => controller.cancelSendInProgress());
    await _settle();
    expect(transferSource.cancelTransferCalls, 1);
    expect(readState().session, isA<SendTransferSession>());
    expect(
      (readState().session as SendTransferSession).phase,
      SendTransferSessionPhase.cancelling,
    );
  });
}

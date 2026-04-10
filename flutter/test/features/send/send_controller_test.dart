import 'package:drift_app/core/models/transfer_models.dart';
import 'package:drift_app/features/send/send_controller.dart';
import 'package:drift_app/features/send/send_providers.dart' as send_deps;
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

    void call(void Function(SendController controller) action) {
      action(container.read(send_deps.sendControllerProvider.notifier));
    }

    call((controller) => controller.pickSendItems());
    await _settle();
    expect(itemSource.pickFilesCalls, 1);
    expect(notifier.applySelectedSendItemsCalls, 1);

    call((controller) => controller.appendSendItemsFromPicker());
    await _settle();
    expect(itemSource.pickAdditionalPathsCalls, 1);
    expect(itemSource.appendPathsCalls, 1);
    expect(notifier.applyPendingSendItemsCalls, 1);
    expect(notifier.applySelectedSendItemsCalls, 2);

    call((controller) => controller.rescanNearbySendDestinations());
    await _settle();
    expect(nearbySource.scanCount, 1);
    expect(notifier.setNearbyScanInFlightCalls, 2);
    expect(notifier.setNearbyDestinationsCalls, 1);

    call((controller) => controller.updateSendDestinationCode('ab2cd3'));
    call((controller) => controller.clearSendDestinationCode());
    expect(notifier.applySendDraftSessionCalls, 2);
    expect(notifier.build().sendDestinationCode, '');

    call(
      (controller) => controller.selectNearbyDestination(
        notifier.build().nearbySendDestinations.first,
      ),
    );
    expect(notifier.applySendDraftSessionCalls, 3);
    expect(notifier.build().selectedSendDestination?.name, 'Lab Mac');

    call((controller) => controller.startSend());
    expect(transferSource.startTransferCalls, 1);
    expect(transferSource.lastRequest?.ticket, 'ticket-123');
    expect(transferSource.lastRequest?.lanDestinationLabel, 'Lab Mac');
    expect(transferSource.lastRequest?.paths, ['sample.txt', 'notes.pdf']);

    call((controller) => controller.cancelSendInProgress());
    expect(notifier.cancelSendInProgressCalls, 1);
  });
}

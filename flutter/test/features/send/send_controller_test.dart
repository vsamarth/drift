import 'package:drift_app/features/send/send_providers.dart';
import 'package:drift_app/state/drift_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'send_test_support.dart';

ProviderContainer _buildContainer(FakeSendAppNotifier notifier) {
  return ProviderContainer(
    overrides: [driftAppNotifierProvider.overrideWith(() => notifier)],
  );
}

void main() {
  test('send controller delegates file and transfer actions', () {
    final notifier = FakeSendAppNotifier(buildSendDraftState());
    final container = _buildContainer(notifier);
    addTearDown(container.dispose);

    final controller = container.read(sendControllerProvider.notifier);

    controller.pickSendItems();
    controller.appendSendItemsFromPicker();
    controller.rescanNearbySendDestinations();
    controller.updateSendDestinationCode('ab2cd3');
    controller.clearSendDestinationCode();
    controller.startSend();
    controller.cancelSendInProgress();
    controller.handleTransferResultPrimaryAction();
    controller.selectNearbyDestination(
      notifier.build().nearbySendDestinations.first,
    );

    expect(notifier.pickSendItemsCalls, 1);
    expect(notifier.appendSendItemsFromPickerCalls, 1);
    expect(notifier.rescanNearbySendDestinationsCalls, 1);
    expect(notifier.updateSendDestinationCodeCalls, 1);
    expect(notifier.clearSendDestinationCodeCalls, 1);
    expect(notifier.startSendCalls, 1);
    expect(notifier.cancelSendInProgressCalls, 1);
    expect(notifier.handleTransferResultPrimaryActionCalls, 1);
    expect(notifier.selectNearbyDestinationCalls, 1);
  });
}

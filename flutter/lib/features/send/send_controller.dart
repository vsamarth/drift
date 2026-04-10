import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/transfer_models.dart';
import '../../state/drift_providers.dart';
import 'send_state.dart';

class SendController extends Notifier<SendState> {
  @override
  SendState build() {
    final appState = ref.watch(driftAppNotifierProvider);
    return SendState.fromAppState(appState);
  }

  void pickSendItems() {
    ref.read(driftAppNotifierProvider.notifier).pickSendItems();
  }

  void appendSendItemsFromPicker() {
    ref.read(driftAppNotifierProvider.notifier).appendSendItemsFromPicker();
  }

  void rescanNearbySendDestinations() {
    ref.read(driftAppNotifierProvider.notifier).rescanNearbySendDestinations();
  }

  void acceptDroppedSendItems(List<String> paths) {
    ref.read(driftAppNotifierProvider.notifier).acceptDroppedSendItems(paths);
  }

  void appendDroppedSendItems(List<String> paths) {
    ref.read(driftAppNotifierProvider.notifier).appendDroppedSendItems(paths);
  }

  void removeSendItem(String path) {
    ref.read(driftAppNotifierProvider.notifier).removeSendItem(path);
  }

  void updateSendDestinationCode(String value) {
    ref
        .read(driftAppNotifierProvider.notifier)
        .updateSendDestinationCode(value);
  }

  void clearSendDestinationCode() {
    ref.read(driftAppNotifierProvider.notifier).clearSendDestinationCode();
  }

  void startSend() {
    ref.read(driftAppNotifierProvider.notifier).startSend();
  }

  void cancelSendInProgress() {
    ref.read(driftAppNotifierProvider.notifier).cancelSendInProgress();
  }

  void handleTransferResultPrimaryAction() {
    ref
        .read(driftAppNotifierProvider.notifier)
        .handleTransferResultPrimaryAction();
  }

  void selectNearbyDestination(SendDestinationViewData destination) {
    ref
        .read(driftAppNotifierProvider.notifier)
        .selectNearbyDestination(destination);
  }
}

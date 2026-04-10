import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/models/transfer_models.dart';
import '../../state/drift_app_state.dart';
import '../../state/drift_providers.dart';
import 'send_flow_actions.dart' as send_flow_actions;
import 'send_dependencies.dart' as send_deps;
import 'send_nearby_coordinator.dart';
import 'send_selection_builder.dart';
import 'send_selection_coordinator.dart';
import 'send_shell_actions.dart' as send_shell_actions;
import 'send_session_controller.dart';
import 'send_transfer_coordinator.dart';
import 'send_state.dart';

part 'send_controller.g.dart';

@Riverpod(keepAlive: true)
class SendController extends _$SendController {
  late SendSelectionCoordinator _sendSelectionCoordinator;
  late SendNearbyCoordinator _sendNearbyCoordinator;
  late SendTransferCoordinator _sendTransferCoordinator;
  late SendSessionController _sendSessionController;

  @override
  SendState build() {
    final appState = ref.watch(driftAppNotifierProvider);
    _sendSelectionCoordinator = SendSelectionCoordinator(
      itemSource: ref.watch(send_deps.sendItemSourceProvider),
      selectionBuilder: const SendSelectionBuilder(),
    );
    _sendNearbyCoordinator = SendNearbyCoordinator(
      nearbyDiscoverySource: ref.watch(send_deps.nearbyDiscoverySourceProvider),
    );
    _sendTransferCoordinator = SendTransferCoordinator(
      transferSource: ref.watch(send_deps.sendTransferSourceProvider),
    );
    _sendSessionController = ref.watch(sendSessionControllerProvider);
    return SendState.fromAppState(appState);
  }

  void pickSendItems() {
    unawaited(
      _sendSelectionCoordinator.pickSendItems(
        ref.read(driftAppNotifierProvider.notifier),
      ),
    );
  }

  void appendSendItemsFromPicker() {
    unawaited(
      _sendSelectionCoordinator.appendSendItemsFromPicker(
        ref.read(driftAppNotifierProvider.notifier),
      ),
    );
  }

  void rescanNearbySendDestinations() {
    unawaited(
      _sendNearbyCoordinator.runScanOnce(
        ref.read(driftAppNotifierProvider.notifier),
      ),
    );
  }

  void acceptDroppedSendItems(List<String> paths) {
    unawaited(
      _sendSelectionCoordinator.acceptDroppedSendItems(
        ref.read(driftAppNotifierProvider.notifier),
        paths,
      ),
    );
  }

  void appendDroppedSendItems(List<String> paths) {
    unawaited(
      _sendSelectionCoordinator.appendDroppedSendItems(
        ref.read(driftAppNotifierProvider.notifier),
        paths,
      ),
    );
  }

  void removeSendItem(String path) {
    unawaited(
      _sendSelectionCoordinator.removeSendItem(
        ref.read(driftAppNotifierProvider.notifier),
        path,
      ),
    );
  }

  void updateSendDestinationCode(String value) {
    final draft = _currentDraft();
    final next = send_shell_actions.updateSendDestinationCode(draft, value);
    if (next == null) {
      return;
    }
    _sendSessionController.applySendDraftSession(
      ref.read(driftAppNotifierProvider.notifier),
      next,
    );
  }

  void clearSendDestinationCode() {
    final draft = _currentDraft();
    final next = send_shell_actions.clearSendDestinationCode(draft);
    if (next == null) {
      return;
    }
    _sendSessionController.applySendDraftSession(
      ref.read(driftAppNotifierProvider.notifier),
      next,
    );
  }

  void startSend() {
    final appState = ref.read(driftAppNotifierProvider);
    final intent = send_flow_actions.buildSendStartIntent(appState);
    if (intent == null) {
      return;
    }

    final host = ref.read(driftAppNotifierProvider.notifier);
    if (intent.ticket != null && intent.destination != null) {
      _sendTransferCoordinator.startSendTransferWithTicket(
        host: host,
        destination: intent.destination!,
        ticket: intent.ticket!,
        onUpdate: (update) =>
            _sendSessionController.applySendTransferUpdate(host, update),
      );
    } else if (intent.normalizedCode != null) {
      _sendTransferCoordinator.startSendTransfer(
        host: host,
        normalizedCode: intent.normalizedCode!,
        onUpdate: (update) =>
            _sendSessionController.applySendTransferUpdate(host, update),
      );
    }
  }

  void cancelSendInProgress() {
    _sendSessionController.cancelSendInProgress(
      ref.read(driftAppNotifierProvider.notifier),
    );
  }

  void handleTransferResultPrimaryAction() {
    final state = ref.read(driftAppNotifierProvider);
    if (state.session is SendResultSession) {
      switch (send_flow_actions.sendPrimaryActionRoute(state.transferResult)) {
        case send_flow_actions.SendFlowRoute.resetShell:
          ref.read(driftAppNotifierProvider.notifier).resetShell();
          return;
        case send_flow_actions.SendFlowRoute.restoreDraft:
          _restoreSendDraft(destinationCode: state.sendDestinationCode);
          return;
        case send_flow_actions.SendFlowRoute.returnToSelection:
          _restoreSendDraft();
          return;
        case send_flow_actions.SendFlowRoute.none:
          return;
      }
    }

    if (state.transferResult != null) {
      ref.read(driftAppNotifierProvider.notifier).resetShell();
    }
  }

  void goBack() {
    final state = ref.read(driftAppNotifierProvider);
    switch (state.session) {
      case SendDraftSession():
        ref.read(driftAppNotifierProvider.notifier).resetShell();
        return;
      case SendTransferSession() || SendResultSession():
        _restoreSendDraft();
        return;
      case ReceiveOfferSession(:final decisionPending):
        if (decisionPending) {
          ref.read(driftAppNotifierProvider.notifier).declineReceiveOffer();
        }
        ref.read(driftAppNotifierProvider.notifier).resetShell();
        return;
      case ReceiveResultSession():
        ref.read(driftAppNotifierProvider.notifier).resetShell();
        return;
      case ReceiveTransferSession():
      case IdleSession():
        return;
    }
  }

  void selectNearbyDestination(SendDestinationViewData destination) {
    final draft = _currentDraft();
    final next = send_shell_actions.selectNearbyDestination(draft, destination);
    if (next == null) {
      return;
    }
    _sendSessionController.applySendDraftSession(
      ref.read(driftAppNotifierProvider.notifier),
      next,
    );
  }

  SendDraftSession? _currentDraft() {
    final session = ref.read(driftAppNotifierProvider).session;
    return session is SendDraftSession ? session : null;
  }

  void _restoreSendDraft({String destinationCode = ''}) {
    final next = send_shell_actions.restoreSendDraft(
      ref.read(driftAppNotifierProvider),
      destinationCode: destinationCode,
    );
    _sendSessionController.applySendDraftSession(
      ref.read(driftAppNotifierProvider.notifier),
      next,
    );
  }
}

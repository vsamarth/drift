import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/models/transfer_models.dart';
import '../../state/drift_app_state.dart';
import '../../state/drift_providers.dart';
import 'send_dependencies.dart' as send_deps;
import 'send_flow_actions.dart' as send_flow_actions;
import 'send_flow_state.dart';
import 'send_nearby_coordinator.dart';
import 'send_selection_builder.dart';
import 'send_selection_coordinator.dart';
import 'send_session_controller.dart';
import 'send_shell_actions.dart' as send_shell_actions;
import 'send_state.dart';
import 'send_transfer_coordinator.dart';

part 'send_controller.g.dart';

@Riverpod(keepAlive: true)
class SendController extends _$SendController
    implements
        SendSelectionHost,
        SendNearbyScanHost,
        SendTransferHost,
        SendSessionHost {
  late SendSelectionCoordinator _sendSelectionCoordinator;
  late SendNearbyCoordinator _sendNearbyCoordinator;
  late SendTransferCoordinator _sendTransferCoordinator;
  late SendSessionController _sendSessionController;

  DriftAppState? _appState;
  ShellSessionState? _appSession;
  ShellSessionState? _sendSession;
  String? _sendSetupErrorMessage;
  Timer? _nearbyScanTimer;

  @override
  SendState build() {
    final appState = ref.watch(driftAppNotifierProvider);
    final appSessionChanged = _appSession != appState.session;
    _appState = appState;
    _appSession = appState.session;
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

    if (_sendSession == null || appSessionChanged) {
      _sendSession = appState.session;
      _sendTransferCoordinator.cancelActiveTransfer();
      _sendSessionController.clearSendMetricState();
      if (appState.session is! SendDraftSession) {
        _cancelNearbyScanTimer();
      }
    }

    _syncNearbyScanTimer();
    ref.onDispose(_dispose);
    return _publishState();
  }

  void pickSendItems() {
    unawaited(
      _sendSelectionCoordinator.pickSendItems(this),
    );
  }

  void appendSendItemsFromPicker() {
    unawaited(
      _sendSelectionCoordinator.appendSendItemsFromPicker(this),
    );
  }

  void rescanNearbySendDestinations() {
    unawaited(
      _sendNearbyCoordinator.runScanOnce(this),
    );
  }

  void acceptDroppedSendItems(List<String> paths) {
    unawaited(
      _sendSelectionCoordinator.acceptDroppedSendItems(this, paths),
    );
  }

  void appendDroppedSendItems(List<String> paths) {
    unawaited(
      _sendSelectionCoordinator.appendDroppedSendItems(this, paths),
    );
  }

  void removeSendItem(String path) {
    unawaited(
      _sendSelectionCoordinator.removeSendItem(this, path),
    );
  }

  void updateSendDestinationCode(String value) {
    final draft = _currentDraft();
    final next = send_shell_actions.updateSendDestinationCode(draft, value);
    if (next == null) {
      return;
    }
    _sendSessionController.applySendDraftSession(this, next);
  }

  void clearSendDestinationCode() {
    final draft = _currentDraft();
    final next = send_shell_actions.clearSendDestinationCode(draft);
    if (next == null) {
      return;
    }
    _sendSessionController.applySendDraftSession(this, next);
  }

  void startSend() {
    final intent = send_flow_actions.buildSendStartIntent(_sendState);
    if (intent == null) {
      return;
    }

    if (intent.ticket != null && intent.destination != null) {
      _sendTransferCoordinator.startSendTransferWithTicket(
        host: this,
        destination: intent.destination!,
        ticket: intent.ticket!,
        onUpdate: (update) =>
            _sendSessionController.applySendTransferUpdate(this, update),
      );
    } else if (intent.normalizedCode != null) {
      _sendTransferCoordinator.startSendTransfer(
        host: this,
        normalizedCode: intent.normalizedCode!,
        onUpdate: (update) =>
            _sendSessionController.applySendTransferUpdate(this, update),
      );
    }
  }

  void cancelSendInProgress() {
    _sendSessionController.cancelSendInProgress(this);
  }

  void handleTransferResultPrimaryAction() {
    final state = _sendState;
    if (state.session is SendResultSession) {
      switch (send_flow_actions.sendPrimaryActionRoute(state.transferResult)) {
        case send_flow_actions.SendFlowRoute.resetShell:
          clearSendFlow();
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
      clearSendFlow();
    }
  }

  void goBack() {
    final state = _sendState;
    switch (state.session) {
      case SendDraftSession():
        clearSendFlow();
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
    _sendSessionController.applySendDraftSession(this, next);
  }

  @override
  List<TransferItemViewData> get currentSendItems => _sendState.sendItems;

  @override
  String get currentDeviceName => _sendState.deviceName;

  @override
  String get currentDeviceType => _sendState.deviceType;

  @override
  String? get currentServerUrl => _appState?.serverUrl ?? ref.read(driftAppNotifierProvider).serverUrl;

  @override
  bool get isInspectingSendItems => _sendState.isInspectingSendItems;

  @override
  bool get nearbyScanInFlight => _sendState.nearbyScanInProgress;

  @override
  void clearSendFlow() {
    _sendSessionController.clearSendFlow(this);
  }

  @override
  void beginSendInspection({required bool clearExistingItems}) {
    _cancelNearbyScanTimer();
    _sendTransferCoordinator.cancelActiveTransfer();
    _sendSession = SendDraftSession(
      items: clearExistingItems ? const [] : _sendState.sendItems,
      isInspecting: true,
      nearbyDestinations: const [],
      nearbyScanInFlight: false,
      nearbyScanCompletedOnce: false,
      destinationCode: '',
    );
    _publishState();
  }

  @override
  void applyPendingSendItems(List<TransferItemViewData> items) {
    final draft = _draftSession;
    if (draft == null || items.isEmpty) {
      return;
    }
    _sendSession = draft.copyWith(
      items: List<TransferItemViewData>.unmodifiable(items),
    );
    _publishState();
  }

  @override
  void applySelectedSendItems(List<TransferItemViewData> items) {
    _sendSession = SendDraftSession(
      items: List<TransferItemViewData>.unmodifiable(items),
      isInspecting: false,
      nearbyDestinations: const [],
      nearbyScanInFlight: false,
      nearbyScanCompletedOnce: false,
      destinationCode: '',
    );
    _publishState();
    _syncNearbyScanTimer();
  }

  @override
  void finishSendInspection() {
    final draft = _draftSession;
    if (draft == null) {
      return;
    }
    _sendSession = draft.copyWith(isInspecting: false);
    _publishState();
    if (draft.items.isNotEmpty) {
      _syncNearbyScanTimer();
    }
  }

  @override
  void clearSendSetupError() {
    _sendSetupErrorMessage = null;
    _publishState();
  }

  @override
  void reportSendSelectionError(
    String userMessage,
    Object error,
    StackTrace stackTrace,
  ) {
    _sendSetupErrorMessage = userMessage;
    _publishState();
    debugPrint('Failed to inspect selected send items: $error');
    debugPrintStack(stackTrace: stackTrace);
  }

  @override
  void setNearbyScanInFlight(bool value) {
    final draft = _draftSession;
    if (draft == null) {
      return;
    }
    _sendSession = draft.copyWith(nearbyScanInFlight: value);
    _publishState();
  }

  @override
  void setNearbyScanCompletedOnce(bool value) {
    final draft = _draftSession;
    if (draft == null) {
      return;
    }
    _sendSession = draft.copyWith(nearbyScanCompletedOnce: value);
    _publishState();
  }

  @override
  void setNearbyDestinations(List<SendDestinationViewData> destinations) {
    final draft = _draftSession;
    if (draft == null) {
      return;
    }
    _sendSession = draft.copyWith(
      nearbyDestinations: List<SendDestinationViewData>.unmodifiable(
        destinations,
      ),
    );
    _publishState();
  }

  @override
  void setSendSetupError(String message) {
    _sendSetupErrorMessage = message;
    _publishState();
  }

  @override
  void clearNearbyScanTimer() {
    _nearbyScanTimer?.cancel();
    _nearbyScanTimer = null;
  }

  @override
  void logNearbyScanFailure(Object error, StackTrace stackTrace) {
    debugPrint('[drift/send] nearby scan failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }

  @override
  void clearSendMetricState() {
    _sendSessionController.clearSendMetricState();
  }

  @override
  void logSendTransferFailure(Object error, StackTrace stackTrace) {
    debugPrint('[drift/send] failed to send files: $error');
    debugPrintStack(stackTrace: stackTrace);
  }

  @override
  void setSendSession(ShellSessionState session) {
    _sendSession = session;
    _publishState();
    _syncNearbyScanTimer();
  }

  @override
  void cancelActiveSendTransfer() {
    _sendTransferCoordinator.cancelActiveTransfer();
  }

  void _restoreSendDraft({String destinationCode = ''}) {
    final next = send_shell_actions.restoreSendDraft(
      _sendState,
      destinationCode: destinationCode,
    );
    _sendSessionController.applySendDraftSession(this, next);
  }

  SendDraftSession? _currentDraft() {
    final session = _sendState.session;
    return session is SendDraftSession ? session : null;
  }

  SendDraftSession? get _draftSession {
    final session = _sendState.session;
    return session is SendDraftSession ? session : null;
  }

  SendState get _sendState {
    final DriftAppState appState =
        _appState ?? ref.read(driftAppNotifierProvider);
    return _buildSendState(
      appState,
      _sendSession ?? appState.session,
    );
  }

  SendState _buildSendState(DriftAppState appState, ShellSessionState session) {
    return SendState(
      identity: appState.identity,
      animateSendingConnection: appState.animateSendingConnection,
      discoverableByDefault: appState.discoverableByDefault,
      session: session,
      sendSetupErrorMessage: _sendSetupErrorMessage,
    );
  }

  SendState _publishState() {
    final DriftAppState appState =
        _appState ?? ref.read(driftAppNotifierProvider);
    final sendState = _buildSendState(
      appState,
      _sendSession ?? appState.session,
    );
    state = sendState;
    return sendState;
  }

  void _syncNearbyScanTimer() {
    _cancelNearbyScanTimer();
    final draft = _draftSession;
    if (draft == null || draft.items.isEmpty || draft.isInspecting) {
      return;
    }

    _sendSession = draft.copyWith(
      nearbyScanCompletedOnce: false,
      nearbyScanInFlight: false,
    );
    _publishState();
    unawaited(_sendNearbyCoordinator.runScanOnce(this));
  }

  void _cancelNearbyScanTimer() {
    _nearbyScanTimer?.cancel();
    _nearbyScanTimer = null;
  }

  void _dispose() {
    _cancelNearbyScanTimer();
    _sendTransferCoordinator.cancelActiveTransfer();
  }

  @override
  SendState get sendState => _sendState;
}

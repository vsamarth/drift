import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/transfer_models.dart';
import '../platform/app_focus.dart';
import '../platform/send_transfer_source.dart';
import '../features/receive/receive_mapper.dart';
import '../features/send/send_selection_builder.dart';
import '../features/send/send_nearby_coordinator.dart';
import '../features/send/send_selection_coordinator.dart';
import '../features/send/send_session_controller.dart';
import '../features/send/send_transfer_coordinator.dart';
import '../src/rust/api/receiver.dart' as rust_receiver;
import '../features/settings/settings_state.dart';
import '../features/settings/settings_providers.dart';
import 'app_identity.dart';
import 'drift_dependencies.dart';
import 'drift_app_state.dart';
import 'nearby_discovery_source.dart';
import 'receiver_service_source.dart';

const List<TransferItemViewData> _defaultDroppedSendItems = [
  TransferItemViewData(
    name: 'sample.txt',
    path: 'sample.txt',
    size: '18 KB',
    kind: TransferItemKind.file,
  ),
  TransferItemViewData(
    name: 'photos',
    path: 'photos/',
    size: '12 items',
    kind: TransferItemKind.folder,
  ),
];

class DriftAppNotifier extends Notifier<DriftAppState>
    implements
        SendSelectionHost,
        SendNearbyScanHost,
        SendTransferHost,
        SendSessionHost {
  late DriftAppIdentity _identity;
  late final SendSelectionCoordinator _sendSelectionCoordinator;
  late final SendNearbyCoordinator _sendNearbyCoordinator;
  late final SendTransferCoordinator _sendTransferCoordinator;
  SendSessionController? _sendSessionController;
  late final SendTransferSource _sendTransferSource;
  late final NearbyDiscoverySource _nearbyDiscoverySource;
  late final ReceiverServiceSource _receiverServiceSource;
  late final bool _animateSendingConnection;
  late final bool _enableIdleIncomingListener;

  Timer? _nearbyScanTimer;
  StreamSubscription<ReceiverBadgeState>? _badgeSubscription;
  StreamSubscription<rust_receiver.ReceiverTransferEvent>?
  _incomingSubscription;
  bool? _appliedDiscoverable;

  DateTime? _receivePayloadStartedAt;

  @override
  DriftAppState build() {
    _identity = ref.watch(initialDriftAppIdentityProvider);
    _sendSelectionCoordinator = SendSelectionCoordinator(
      itemSource: ref.watch(sendItemSourceProvider),
      selectionBuilder: const SendSelectionBuilder(),
    );
    _nearbyDiscoverySource = ref.watch(nearbyDiscoverySourceProvider);
    _sendNearbyCoordinator = SendNearbyCoordinator(
      nearbyDiscoverySource: _nearbyDiscoverySource,
    );
    _sendTransferSource = ref.watch(sendTransferSourceProvider);
    _sendTransferCoordinator = SendTransferCoordinator(
      transferSource: _sendTransferSource,
    );
    _sendSessionController = ref.watch(sendSessionControllerProvider);
    _receiverServiceSource = ref.watch(receiverServiceSourceProvider);
    _animateSendingConnection = ref.watch(animateSendingConnectionProvider);
    _enableIdleIncomingListener = ref.watch(enableIdleIncomingListenerProvider);

    ref.onDispose(_dispose);

    _startReceiverSubscriptions();
    Future<void>.microtask(_syncDiscoverabilityPolicy);
    ref.listen(settingsControllerProvider, _onSettingsStateChanged);

    return DriftAppState(
      identity: _identity,
      receiverBadge: const ReceiverBadgeState.registering(),
      session: const IdleSession(),
      animateSendingConnection: _animateSendingConnection,
      sendSetupErrorMessage: null,
    );
  }

  void _onSettingsStateChanged(SettingsState? previous, SettingsState next) {
    if (previous?.identity == next.identity) {
      return;
    }

    _identity = next.identity;
    state = state.copyWith(
      identity: next.identity,
      receiverBadge: const ReceiverBadgeState.registering(),
    );
    _startReceiverSubscriptions();
    _syncSessionPolicies();
  }

  void setMode(TransferDirection mode) {
    resetShell();
  }

  void activateSendDropTarget() {
    _applySelectedSendItems(_defaultDroppedSendItems);
  }

  void pickSendItems() {
    unawaited(_sendSelectionCoordinator.pickSendItems(this));
  }

  void appendSendItemsFromPicker() {
    unawaited(_sendSelectionCoordinator.appendSendItemsFromPicker(this));
  }

  void rescanNearbySendDestinations() {
    unawaited(_sendNearbyCoordinator.runScanOnce(this));
  }

  void acceptDroppedSendItems(List<String> paths) {
    unawaited(_sendSelectionCoordinator.acceptDroppedSendItems(this, paths));
  }

  void appendDroppedSendItems(List<String> paths) {
    unawaited(_sendSelectionCoordinator.appendDroppedSendItems(this, paths));
  }

  void removeSendItem(String path) {
    unawaited(_sendSelectionCoordinator.removeSendItem(this, path));
  }

  @override
  void clearSendFlow() {
    _sendSessionControllerInstance.clearSendFlow(this);
  }

  void acceptReceiveOffer() {
    final session = state.session;
    if (session is! ReceiveOfferSession) {
      return;
    }

    if (!session.decisionPending) {
      _setSession(
        ReceiveResultSession(
          success: true,
          outcome: TransferResultOutcomeData.success,
          items: session.items,
          summary: session.summary.copyWith(
            statusMessage: 'Saved to ${session.summary.destinationLabel}',
          ),
        ),
      );
      return;
    }

    _clearReceiveMetricState();
    _setSession(
      ReceiveTransferSession(
        items: session.items,
        summary: session.summary.copyWith(statusMessage: 'Receiving files...'),
        payloadBytesReceived: null,
        payloadTotalBytes: session.payloadTotalBytes,
      ),
    );
    unawaited(_respondToIncomingOffer(accept: true));
  }

  void declineReceiveOffer() {
    final session = state.session;
    if (session is ReceiveOfferSession && session.decisionPending) {
      unawaited(_respondToIncomingOffer(accept: false));
      return;
    }
    resetShell();
  }

  void cancelSendInProgress() {
    _sendSessionControllerInstance.cancelSendInProgress(this);
  }

  void cancelReceiveInProgress() {
    final session = state.session;
    if (session is! ReceiveTransferSession) {
      return;
    }
    _setSession(
      session.copyWith(
        summary: session.summary.copyWith(
          statusMessage: 'Cancelling transfer...',
        ),
      ),
    );
    unawaited(_cancelNativeReceiveTransfer());
  }

  void resetShell() {
    _cancelNearbyScanTimer();
    _cancelActiveSendTransfer();
    _sendSessionControllerInstance.clearSendMetricState();
    _clearReceiveMetricState();
    state = state.copyWith(clearSendSetupErrorMessage: true);
    _setSession(const IdleSession());
  }

  @override
  void applySelectedSendItems(List<TransferItemViewData> items) {
    _applySelectedSendItems(items);
  }

  @override
  void applyPendingSendItems(List<TransferItemViewData> items) {
    _applyPendingSendItems(items);
  }

  @override
  void beginSendInspection({required bool clearExistingItems}) {
    _beginSendInspection(clearExistingItems: clearExistingItems);
  }

  @override
  void finishSendInspection() {
    _finishSendInspection();
  }

  @override
  void clearSendSetupError() {
    _clearSendSetupError();
  }

  @override
  void reportSendSelectionError(
    String userMessage,
    Object error,
    StackTrace stackTrace,
  ) {
    _reportSendSelectionError(userMessage, error, stackTrace);
  }

  @override
  List<TransferItemViewData> get currentSendItems => state.sendItems;

  @override
  String get currentDeviceName => state.deviceName;

  @override
  String get currentDeviceType => state.deviceType;

  @override
  String? get currentServerUrl => state.serverUrl;

  @override
  void logSendTransferFailure(Object error, StackTrace stackTrace) {
    debugPrint('[drift/notifier] failed to send files: $error');
    debugPrintStack(stackTrace: stackTrace);
  }

  @override
  void clearSendMetricState() {
    _sendSessionControllerInstance.clearSendMetricState();
  }

  @override
  bool get isInspectingSendItems => state.isInspectingSendItems;

  @override
  bool get nearbyScanInFlight => state.nearbyScanInProgress;

  @override
  void setNearbyScanInFlight(bool value) {
    final draft = _draftSession;
    if (draft == null) {
      return;
    }
    _setSession(draft.copyWith(nearbyScanInFlight: value));
  }

  @override
  void setNearbyScanCompletedOnce(bool value) {
    final draft = _draftSession;
    if (draft == null) {
      return;
    }
    _setSession(draft.copyWith(nearbyScanCompletedOnce: value));
  }

  @override
  void setNearbyDestinations(List<SendDestinationViewData> destinations) {
    final draft = _draftSession;
    if (draft == null) {
      return;
    }
    _setSession(
      draft.copyWith(
        nearbyDestinations: List<SendDestinationViewData>.unmodifiable(
          destinations,
        ),
      ),
    );
  }

  @override
  void setSendSetupError(String message) {
    _setSendSetupError(message);
  }

  @override
  void clearNearbyScanTimer() {
    _cancelNearbyScanTimer();
  }

  @override
  void cancelActiveSendTransfer() {
    _cancelActiveSendTransfer();
  }

  @override
  void logNearbyScanFailure(Object error, StackTrace stackTrace) {
    debugPrint('[drift/notifier] nearby scan failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }

  void _applySelectedSendItems(List<TransferItemViewData> items) {
    _cancelActiveSendTransfer();
    state = state.copyWith(clearSendSetupErrorMessage: true);
    _setSession(
      SendDraftSession(
        items: List<TransferItemViewData>.unmodifiable(items),
        isInspecting: false,
        nearbyDestinations: const [],
        nearbyScanInFlight: false,
        nearbyScanCompletedOnce: false,
        destinationCode: '',
      ),
    );
    _scheduleNearbyScanning();
  }

  void _applyPendingSendItems(List<TransferItemViewData> items) {
    final draft = _draftSession;
    if (draft == null || items.isEmpty) {
      return;
    }
    _setSession(
      draft.copyWith(items: List<TransferItemViewData>.unmodifiable(items)),
    );
  }

  void _beginSendInspection({required bool clearExistingItems}) {
    _cancelNearbyScanTimer();
    _cancelActiveSendTransfer();
    _setSession(
      SendDraftSession(
        items: clearExistingItems ? const [] : state.sendItems,
        isInspecting: true,
        nearbyDestinations: const [],
        nearbyScanInFlight: false,
        nearbyScanCompletedOnce: false,
        destinationCode: '',
      ),
    );
  }

  void _finishSendInspection() {
    final draft = _draftSession;
    if (draft == null) {
      return;
    }
    _setSession(draft.copyWith(isInspecting: false));
    if (draft.items.isNotEmpty) {
      _scheduleNearbyScanning();
    }
  }

  void _startReceiverSubscriptions() {
    _badgeSubscription?.cancel();
    _badgeSubscription = _receiverServiceSource
        .watchBadge(_identity)
        .listen(
          (badge) {
            state = state.copyWith(receiverBadge: badge);
          },
          onError: (Object error, StackTrace stackTrace) {
            debugPrint('watchBadge failed: $error');
            debugPrintStack(stackTrace: stackTrace);
            state = state.copyWith(
              receiverBadge: const ReceiverBadgeState.unavailable(),
            );
          },
        );

    if (!_enableIdleIncomingListener) {
      return;
    }

    _incomingSubscription?.cancel();
    _incomingSubscription = _receiverServiceSource
        .watchIncomingTransfers(_identity)
        .listen(
          _onIncomingEvent,
          onError: (Object error, StackTrace stackTrace) {
            debugPrint('watchIncomingTransfers failed: $error');
            debugPrintStack(stackTrace: stackTrace);
            _applyIncomingFailure(
              errorMessage: 'Drift lost the connection while receiving files.',
            );
          },
        );
  }

  void _onIncomingEvent(rust_receiver.ReceiverTransferEvent event) {
    switch (event.phase) {
      case rust_receiver.ReceiverTransferPhase.connecting:
        return;
      case rust_receiver.ReceiverTransferPhase.offerReady:
        _applyIncomingOffer(event);
        return;
      case rust_receiver.ReceiverTransferPhase.receiving:
        _applyIncomingReceiving(event);
        return;
      case rust_receiver.ReceiverTransferPhase.completed:
        _applyIncomingCompleted(event);
        return;
      case rust_receiver.ReceiverTransferPhase.cancelled:
        _applyIncomingCancelled(event);
        return;
      case rust_receiver.ReceiverTransferPhase.failed:
        debugPrint(
          '[drift/notifier] incoming receive failed: '
          '${event.error?.message ?? event.statusMessage}',
        );
        _applyIncomingFailed(event);
        return;
      case rust_receiver.ReceiverTransferPhase.declined:
        _applyIncomingDeclined(event);
        return;
    }
  }

  void _applyIncomingOffer(rust_receiver.ReceiverTransferEvent event) {
    final items = List<TransferItemViewData>.unmodifiable(
      event.files.map(incomingFileToViewData),
    );
    _cancelActiveSendTransfer();
    _clearReceiveMetricState();
    _setSession(
      ReceiveOfferSession(
        items: items,
        summary: TransferSummaryViewData(
          itemCount: _bigIntToInt(event.itemCount),
          totalSize: event.totalSizeLabel,
          code: state.idleReceiveCode,
          expiresAt: '',
          destinationLabel: event.saveRootLabel.isNotEmpty
              ? event.saveRootLabel
              : 'Downloads',
          statusMessage: event.statusMessage,
          senderName: event.senderName,
        ),
        decisionPending: true,
        payloadTotalBytes: _bigIntToInt(event.totalSizeBytes),
        plan: event.plan,
        snapshot: event.snapshot,
        senderDeviceType: event.senderDeviceType,
      ),
    );
    unawaited(focusAppForIncomingTransfer());
  }

  void _applyIncomingReceiving(rust_receiver.ReceiverTransferEvent event) {
    final progress = progressFromSnapshot(event.snapshot);
    final payloadBytesReceived =
        progress.bytesTransferred ?? _bigIntToInt(event.bytesReceived);
    final payloadTotalBytes =
        progress.totalBytes ?? _bigIntToInt(event.totalSizeBytes);
    if (_receivePayloadStartedAt == null && payloadBytesReceived > 0) {
      _receivePayloadStartedAt = DateTime.now();
    }

    final currentSummary =
        state.receiveSummary ??
        TransferSummaryViewData(
          itemCount: _bigIntToInt(event.itemCount),
          totalSize: event.totalSizeLabel,
          code: state.idleReceiveCode,
          expiresAt: '',
          destinationLabel: event.destinationLabel,
          statusMessage: event.statusMessage,
          senderName: event.senderName,
        );

    _setSession(
      ReceiveTransferSession(
        items: state.receiveItems,
        summary: currentSummary.copyWith(statusMessage: event.statusMessage),
        plan: event.plan ?? state.receiveTransferPlan,
        snapshot: event.snapshot,
        payloadBytesReceived: payloadBytesReceived,
        payloadTotalBytes: payloadTotalBytes,
        payloadSpeedLabel: progress.speedLabel,
        payloadEtaLabel: progress.etaLabel,
        senderDeviceType: event.senderDeviceType,
      ),
    );
  }

  void _applyIncomingCompleted(rust_receiver.ReceiverTransferEvent event) {
    final progress = progressFromSnapshot(event.snapshot);
    final bytesReceived =
        progress.bytesTransferred ?? _bigIntToInt(event.bytesReceived);
    final totalBytes =
        progress.totalBytes ?? _bigIntToInt(event.totalSizeBytes);
    if (_receivePayloadStartedAt == null && bytesReceived > 0) {
      _receivePayloadStartedAt = DateTime.now();
    }
    final summary =
        state.receiveSummary ??
        TransferSummaryViewData(
          itemCount: _bigIntToInt(event.itemCount),
          totalSize: event.totalSizeLabel,
          code: state.idleReceiveCode,
          expiresAt: '',
          destinationLabel: event.saveRootLabel,
          statusMessage: event.statusMessage,
          senderName: event.senderName,
        );
    final completedSummary = summary.copyWith(
      itemCount: _bigIntToInt(event.itemCount),
      totalSize: event.totalSizeLabel,
      destinationLabel: event.saveRootLabel,
      statusMessage: event.statusMessage,
    );
    _setSession(
      ReceiveResultSession(
        success: true,
        outcome: TransferResultOutcomeData.success,
        items: state.receiveItems,
        summary: completedSummary,
        metrics: buildReceiveCompletionMetrics(
          summary: completedSummary,
          bytesReceived: bytesReceived,
          startedAt: _receivePayloadStartedAt,
        ),
        plan: event.plan ?? state.receiveTransferPlan,
        snapshot: event.snapshot,
        payloadBytesReceived: bytesReceived,
        payloadTotalBytes: totalBytes,
        senderDeviceType: event.senderDeviceType,
      ),
    );
    _clearReceiveMetricState();
  }

  void _applyIncomingCancelled(rust_receiver.ReceiverTransferEvent event) {
    final progress = progressFromSnapshot(event.snapshot);
    final bytesReceived =
        progress.bytesTransferred ?? _bigIntToInt(event.bytesReceived);
    final totalBytes =
        progress.totalBytes ?? _bigIntToInt(event.totalSizeBytes);
    if (_receivePayloadStartedAt == null && bytesReceived > 0) {
      _receivePayloadStartedAt = DateTime.now();
    }
    final summary =
        state.receiveSummary ??
        TransferSummaryViewData(
          itemCount: _bigIntToInt(event.itemCount),
          totalSize: event.totalSizeLabel,
          code: state.idleReceiveCode,
          expiresAt: '',
          destinationLabel: event.saveRootLabel,
          statusMessage: event.error?.message ?? event.statusMessage,
          senderName: event.senderName,
        );
    _setSession(
      ReceiveResultSession(
        success: false,
        outcome: TransferResultOutcomeData.cancelled,
        items: state.receiveItems,
        summary: summary.copyWith(
          destinationLabel: event.saveRootLabel,
          statusMessage: event.error?.message ?? event.statusMessage,
        ),
        plan: event.plan ?? state.receiveTransferPlan,
        snapshot: event.snapshot,
        payloadBytesReceived: bytesReceived,
        payloadTotalBytes: totalBytes,
        senderDeviceType: event.senderDeviceType,
      ),
    );
    _clearReceiveMetricState();
  }

  void _applyIncomingFailed(rust_receiver.ReceiverTransferEvent event) {
    _applyIncomingFailure(
      errorMessage: event.error?.message ?? event.statusMessage,
      event: event,
    );
  }

  void _applyIncomingDeclined(rust_receiver.ReceiverTransferEvent event) {
    final summary =
        state.receiveSummary ??
        TransferSummaryViewData(
          itemCount: _bigIntToInt(event.itemCount),
          totalSize: event.totalSizeLabel,
          code: state.idleReceiveCode,
          expiresAt: '',
          destinationLabel: event.saveRootLabel.isNotEmpty
              ? event.saveRootLabel
              : 'Downloads',
          statusMessage: event.error?.message ?? event.statusMessage,
          senderName: event.senderName,
        );

    _setSession(
      ReceiveResultSession(
        success: false,
        outcome: TransferResultOutcomeData.declined,
        items: state.receiveItems,
        summary: summary.copyWith(
          destinationLabel: event.saveRootLabel.isNotEmpty
              ? event.saveRootLabel
              : summary.destinationLabel,
          statusMessage: event.error?.message ?? event.statusMessage,
          senderName: event.senderName.isNotEmpty
              ? event.senderName
              : summary.senderName,
        ),
        plan: event.plan ?? state.receiveTransferPlan,
        snapshot: event.snapshot ?? state.receiveTransferSnapshot,
        payloadBytesReceived: state.receivePayloadBytesReceived,
        payloadTotalBytes:
            state.receivePayloadTotalBytes ??
            _bigIntToInt(event.totalSizeBytes),
        senderDeviceType: event.senderDeviceType,
      ),
    );
    _clearReceiveMetricState();
  }

  void _applyIncomingFailure({
    required String errorMessage,
    rust_receiver.ReceiverTransferEvent? event,
  }) {
    final progress = progressFromSnapshot(
      event?.snapshot ?? state.receiveTransferSnapshot,
    );
    final bytesReceived =
        progress.bytesTransferred ??
        (event == null
            ? state.receivePayloadBytesReceived
            : _bigIntToInt(event.bytesReceived)) ??
        0;
    final totalBytes =
        progress.totalBytes ??
        (event == null
            ? state.receivePayloadTotalBytes
            : _bigIntToInt(event.totalSizeBytes));
    if (_receivePayloadStartedAt == null && bytesReceived > 0) {
      _receivePayloadStartedAt = DateTime.now();
    }

    final summary =
        state.receiveSummary ??
        TransferSummaryViewData(
          itemCount: event == null
              ? state.receiveItems.length
              : _bigIntToInt(event.itemCount),
          totalSize: event?.totalSizeLabel ?? '',
          code: state.idleReceiveCode,
          expiresAt: '',
          destinationLabel: event?.saveRootLabel ?? state.downloadRoot,
          statusMessage: errorMessage,
          senderName: event?.senderName ?? '',
        );

    _setSession(
      ReceiveResultSession(
        success: false,
        outcome: TransferResultOutcomeData.failed,
        items: state.receiveItems,
        summary: summary.copyWith(
          itemCount: event == null
              ? summary.itemCount
              : _bigIntToInt(event.itemCount),
          totalSize: event?.totalSizeLabel ?? summary.totalSize,
          destinationLabel: event?.saveRootLabel.isNotEmpty == true
              ? event!.saveRootLabel
              : summary.destinationLabel,
          statusMessage: errorMessage,
          senderName: event?.senderName ?? summary.senderName,
        ),
        plan: event?.plan ?? state.receiveTransferPlan,
        snapshot: event?.snapshot ?? state.receiveTransferSnapshot,
        payloadBytesReceived: bytesReceived,
        payloadTotalBytes: totalBytes,
        senderDeviceType:
            event?.senderDeviceType ?? state.receiveSenderDeviceType,
      ),
    );
    _clearReceiveMetricState();
  }

  Future<void> _respondToIncomingOffer({required bool accept}) async {
    try {
      await _receiverServiceSource.respondToOffer(accept: accept);
    } catch (error, stackTrace) {
      debugPrint('respondToOffer failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _applyIncomingFailure(
        errorMessage: accept
            ? 'Drift couldn\'t accept the transfer.'
            : 'Drift couldn\'t decline the transfer.',
      );
    }
  }

  Future<void> _cancelNativeReceiveTransfer() async {
    try {
      await _receiverServiceSource.cancelTransfer();
    } catch (error, stackTrace) {
      debugPrint('cancelReceiveTransfer failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _applyIncomingFailure(
        errorMessage: 'Drift couldn\'t cancel the transfer.',
      );
    }
  }

  void _scheduleNearbyScanning() {
    _cancelNearbyScanTimer();
    final draft = _draftSession;
    if (draft == null || draft.items.isEmpty || draft.isInspecting) {
      return;
    }
    _setSession(
      draft.copyWith(nearbyScanCompletedOnce: false, nearbyScanInFlight: false),
    );
    unawaited(_sendNearbyCoordinator.runScanOnce(this));
    _nearbyScanTimer = Timer.periodic(
      _sendNearbyCoordinator.refreshIntervalForDeviceType(_identity.deviceType),
      (_) {
        final current = _draftSession;
        if (current == null || current.items.isEmpty || current.isInspecting) {
          _cancelNearbyScanTimer();
          return;
        }
        unawaited(_sendNearbyCoordinator.runScanOnce(this));
      },
    );
  }

  void applySendTransferUpdate(SendTransferUpdate update) {
    _sendSessionControllerInstance.applySendTransferUpdate(this, update);
  }

  void applySendDraftSession(SendDraftSession session) {
    _sendSessionControllerInstance.applySendDraftSession(this, session);
  }

  @override
  DriftAppState get sendAppState => state;

  @override
  void setSendSession(ShellSessionState session) {
    _setSession(session);
  }

  void _setSession(ShellSessionState session) {
    state = state.copyWith(session: session);
    _syncSessionPolicies();
  }

  void _syncSessionPolicies() {
    unawaited(_syncDiscoverabilityPolicy());
    if (state.session is! SendDraftSession) {
      _cancelNearbyScanTimer();
    }
  }

  Future<void> _syncDiscoverabilityPolicy() async {
    final desired = state.discoverableEnabled;
    if (_appliedDiscoverable == desired) {
      return;
    }
    _appliedDiscoverable = desired;
    try {
      await _receiverServiceSource.setDiscoverable(enabled: desired);
    } catch (error, stackTrace) {
      debugPrint('setDiscoverable($desired) failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  void _cancelNearbyScanTimer() {
    _nearbyScanTimer?.cancel();
    _nearbyScanTimer = null;
  }

  SendDraftSession? get _draftSession {
    final session = state.session;
    return session is SendDraftSession ? session : null;
  }

  void _reportSendSelectionError(
    String userMessage,
    Object error,
    StackTrace stackTrace,
  ) {
    _setSendSetupError(userMessage);
    debugPrint('Failed to inspect selected send items: $error');
    debugPrintStack(stackTrace: stackTrace);
  }

  void _setSendSetupError(String message) {
    state = state.copyWith(sendSetupErrorMessage: message);
  }

  void _clearSendSetupError() {
    state = state.copyWith(clearSendSetupErrorMessage: true);
  }

  void _cancelActiveSendTransfer() {
    _sendTransferCoordinator.cancelActiveTransfer();
  }

  SendSessionController get _sendSessionControllerInstance {
    final controller = _sendSessionController;
    if (controller != null) {
      return controller;
    }
    final next = ref.read(sendSessionControllerProvider);
    _sendSessionController = next;
    return next;
  }

  void _clearReceiveMetricState() {
    _receivePayloadStartedAt = null;
  }

  void _dispose() {
    _cancelNearbyScanTimer();
    _sendTransferCoordinator.cancelActiveTransfer();
    _badgeSubscription?.cancel();
    _incomingSubscription?.cancel();
  }
}

int _bigIntToInt(BigInt value) {
  if (value.bitLength > 63) {
    return 0x7fffffffffffffff;
  }
  return value.toInt();
}

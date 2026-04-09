import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/transfer_models.dart';
import '../platform/app_focus.dart';
import '../platform/send_item_source.dart';
import '../platform/send_transfer_source.dart';
import '../src/rust/api/receiver.dart' as rust_receiver;
import '../src/rust/api/transfer.dart' as rust_transfer;
import '../state/drift_sample_data.dart';
import 'app_identity.dart';
import 'drift_dependencies.dart';
import 'drift_app_state.dart';
import 'nearby_discovery_source.dart';
import 'receiver_service_source.dart';
import 'settings_store.dart';

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

class DriftAppNotifier extends Notifier<DriftAppState> {
  late DriftAppIdentity _identity;
  late final SendItemSource _sendItemSource;
  late final SendTransferSource _sendTransferSource;
  late final NearbyDiscoverySource _nearbyDiscoverySource;
  late final ReceiverServiceSource _receiverServiceSource;
  late final DriftSettingsStore _settingsStore;
  late final bool _animateSendingConnection;
  late final bool _enableIdleIncomingListener;

  Timer? _nearbyScanTimer;
  StreamSubscription<ReceiverBadgeState>? _badgeSubscription;
  StreamSubscription<rust_receiver.ReceiverTransferEvent>?
  _incomingSubscription;
  StreamSubscription<SendTransferUpdate>? _sendTransferSubscription;
  int _sendTransferGeneration = 0;
  bool? _appliedDiscoverable;

  DateTime? _sendPayloadStartedAt;
  DateTime? _receivePayloadStartedAt;

  @override
  DriftAppState build() {
    _identity = ref.watch(initialDriftAppIdentityProvider);
    _sendItemSource = ref.watch(sendItemSourceProvider);
    _sendTransferSource = ref.watch(sendTransferSourceProvider);
    _nearbyDiscoverySource = ref.watch(nearbyDiscoverySourceProvider);
    _receiverServiceSource = ref.watch(receiverServiceSourceProvider);
    _settingsStore = ref.watch(driftSettingsStoreProvider);
    _animateSendingConnection = ref.watch(animateSendingConnectionProvider);
    _enableIdleIncomingListener = ref.watch(enableIdleIncomingListenerProvider);

    ref.onDispose(_dispose);

    _startReceiverSubscriptions();
    Future<void>.microtask(_syncDiscoverabilityPolicy);

    return DriftAppState(
      identity: _identity,
      receiverBadge: const ReceiverBadgeState.registering(),
      session: const IdleSession(),
      animateSendingConnection: _animateSendingConnection,
      sendSetupErrorMessage: null,
    );
  }

  Future<void> saveSettings({
    required String deviceName,
    required String downloadRoot,
    required bool discoverableByDefault,
    String? serverUrl,
  }) async {
    final nextIdentity = buildDefaultDriftAppIdentity(
      deviceName: deviceName,
      deviceType: _identity.deviceType,
      downloadRoot: downloadRoot,
      serverUrl: serverUrl,
      discoverable: discoverableByDefault,
    );

    if (nextIdentity == _identity) {
      return;
    }

    await _settingsStore.save(nextIdentity);
    _identity = nextIdentity;
    state = state.copyWith(
      identity: nextIdentity,
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
    unawaited(_pickSendItems());
  }

  void appendSendItemsFromPicker() {
    unawaited(_appendSendItemsFromPicker());
  }

  void rescanNearbySendDestinations() {
    unawaited(_runNearbyScanOnce());
  }

  void acceptDroppedSendItems(List<String> paths) {
    unawaited(_acceptDroppedSendItems(paths));
  }

  void appendDroppedSendItems(List<String> paths) {
    unawaited(_appendDroppedSendItems(paths));
  }

  void removeSendItem(String path) {
    unawaited(_removeSendItem(path));
  }

  void clearSendFlow() {
    _cancelNearbyScanTimer();
    _cancelActiveSendTransfer();
    _setSession(const IdleSession());
  }

  void updateSendDestinationCode(String value) {
    final draft = _draftSession;
    if (draft == null) {
      return;
    }
    final normalized = value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (normalized == draft.destinationCode) {
      return;
    }
    _setSession(
      draft.copyWith(
        destinationCode: normalized,
        clearSelectedDestination: true,
      ),
    );
  }

  void clearSendDestinationCode() {
    final draft = _draftSession;
    if (draft == null) {
      return;
    }
    _setSession(draft.copyWith(destinationCode: ''));
  }

  void startSend() {
    final draft = _draftSession;
    if (draft == null || draft.items.isEmpty || draft.isInspecting) {
      return;
    }

    final selected = draft.selectedDestination;
    final ticket = selected?.lanTicket?.trim();

    if (selected != null && ticket != null && ticket.isNotEmpty) {
      _startSendTransferWithTicket(selected, ticket);
    } else if (draft.destinationCode.length == 6) {
      _startSendTransfer(draft.destinationCode);
    }
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
    final session = state.session;
    if (session is! SendTransferSession) {
      return;
    }
    _setSession(
      session.copyWith(
        phase: SendTransferSessionPhase.cancelling,
        summary: session.summary.copyWith(
          statusMessage: 'Cancelling transfer...',
        ),
      ),
    );
    unawaited(_cancelNativeSendTransfer());
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
    _clearSendMetricState();
    _clearReceiveMetricState();
    state = state.copyWith(clearSendSetupErrorMessage: true);
    _setSession(const IdleSession());
  }

  void handleTransferResultPrimaryAction() {
    final result = state.transferResult;
    if (result == null) {
      return;
    }

    switch (result.primaryAction) {
      case TransferResultPrimaryActionData.done:
      case null:
        resetShell();
      case TransferResultPrimaryActionData.tryAgain:
      case TransferResultPrimaryActionData.sendAgain:
        _restoreSendDraft(destinationCode: state.sendDestinationCode);
      case TransferResultPrimaryActionData.chooseAnotherDevice:
        _returnToSendSelection();
    }
  }

  void goBack() {
    switch (state.session) {
      case ReceiveOfferSession(:final decisionPending):
        if (decisionPending) {
          unawaited(_respondToIncomingOffer(accept: false));
        }
        _setSession(const IdleSession());
      case ReceiveResultSession():
        _setSession(const IdleSession());
      case SendDraftSession():
        _setSession(const IdleSession());
      case SendTransferSession():
        _returnToSendSelection();
      case SendResultSession():
        _returnToSendSelection();
      case ReceiveTransferSession():
      case IdleSession():
        return;
    }
  }

  void selectNearbyDestination(SendDestinationViewData destination) {
    final draft = _draftSession;
    if (draft == null) {
      return;
    }
    // Toggle selection
    if (draft.selectedDestination == destination) {
      _setSession(draft.copyWith(clearSelectedDestination: true));
    } else {
      _setSession(
        draft.copyWith(
          selectedDestination: destination,
          destinationCode: '', // Clear code if nearby is selected
        ),
      );
    }
  }

  Future<void> _pickSendItems() async {
    try {
      final items = await _sendItemSource.pickFiles();
      if (items.isEmpty) {
        return;
      }
      _clearSendSetupError();
      _beginSendInspection(clearExistingItems: true);
      _applySelectedSendItems(items);
    } catch (error, stackTrace) {
      clearSendFlow();
      _reportSendSelectionError(
        'Drift couldn\'t prepare the selected files.',
        error,
        stackTrace,
      );
    }
  }

  Future<void> _acceptDroppedSendItems(List<String> paths) async {
    if (paths.isEmpty) {
      return;
    }
    _beginSendInspection(clearExistingItems: true);
    try {
      final items = await _sendItemSource.loadPaths(paths);
      if (items.isEmpty) {
        clearSendFlow();
        return;
      }
      _clearSendSetupError();
      _applySelectedSendItems(items);
    } catch (error, stackTrace) {
      clearSendFlow();
      _reportSendSelectionError(
        'Drift couldn\'t prepare the dropped files.',
        error,
        stackTrace,
      );
    }
  }

  Future<void> _appendDroppedSendItems(List<String> paths) async {
    if (paths.isEmpty) {
      return;
    }
    _beginSendInspection(clearExistingItems: false);
    _optimisticallyAppendPendingSendItems(paths);
    try {
      final items = await _sendItemSource.appendPaths(
        existingPaths: _currentSendSelectionPaths,
        incomingPaths: paths,
      );
      if (items.isEmpty) {
        _finishSendInspection();
        return;
      }
      _clearSendSetupError();
      _applySelectedSendItems(items);
    } catch (error, stackTrace) {
      _finishSendInspection();
      _reportSendSelectionError(
        'Drift couldn\'t add those files right now.',
        error,
        stackTrace,
      );
    }
  }

  Future<void> _appendSendItemsFromPicker() async {
    final paths = await _sendItemSource.pickAdditionalPaths();
    if (paths.isEmpty) {
      return;
    }
    _beginSendInspection(clearExistingItems: false);
    _optimisticallyAppendPendingSendItems(paths);
    try {
      final items = await _sendItemSource.appendPaths(
        existingPaths: _currentSendSelectionPaths,
        incomingPaths: paths,
      );
      if (items.isEmpty) {
        _finishSendInspection();
        return;
      }
      _clearSendSetupError();
      _applySelectedSendItems(items);
    } catch (error, stackTrace) {
      _finishSendInspection();
      _reportSendSelectionError(
        'Drift couldn\'t add those files right now.',
        error,
        stackTrace,
      );
    }
  }

  Future<void> _removeSendItem(String path) async {
    final draft = _draftSession;
    if (draft == null || path.trim().isEmpty) {
      return;
    }
    _beginSendInspection(clearExistingItems: false);
    try {
      final items = await _sendItemSource.removePath(
        existingPaths: _currentSendSelectionPaths,
        removedPath: path,
      );
      if (items.isEmpty) {
        clearSendFlow();
        return;
      }
      _clearSendSetupError();
      _applySelectedSendItems(items);
    } catch (error, stackTrace) {
      _finishSendInspection();
      _reportSendSelectionError(
        'Drift couldn\'t update the selected files.',
        error,
        stackTrace,
      );
    }
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

  void _optimisticallyAppendPendingSendItems(List<String> incomingPaths) {
    final draft = _draftSession;
    if (draft == null || incomingPaths.isEmpty) {
      return;
    }

    final seen = draft.items.map((item) => item.path.trim()).toSet();
    final mergedItems = List<TransferItemViewData>.of(draft.items);

    for (final rawPath in incomingPaths) {
      final path = rawPath.trim();
      if (path.isEmpty || !seen.add(path)) {
        continue;
      }
      mergedItems.add(_pendingSendItemForPath(path));
    }

    _setSession(
      draft.copyWith(
        items: List<TransferItemViewData>.unmodifiable(mergedItems),
      ),
    );
  }

  TransferItemViewData _pendingSendItemForPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final trimmed = normalized.endsWith('/')
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
    final segments = trimmed.split('/')
      ..removeWhere((segment) => segment.isEmpty);
    final name = segments.isEmpty ? trimmed : segments.last;
    final isFolder = normalized.endsWith('/');

    return TransferItemViewData(
      name: name.isEmpty ? path : name,
      path: path,
      size: 'Adding...',
      kind: isFolder ? TransferItemKind.folder : TransferItemKind.file,
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
      event.files.map(_incomingFileToViewData),
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
    final progress = _progressFromSnapshot(event.snapshot);
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
    final progress = _progressFromSnapshot(event.snapshot);
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
        metrics: _buildReceiveCompletionMetrics(
          summary: completedSummary,
          bytesReceived: bytesReceived,
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
    final progress = _progressFromSnapshot(event.snapshot);
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
    final progress = _progressFromSnapshot(
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

  TransferItemViewData _incomingFileToViewData(
    rust_receiver.ReceiverTransferFile file,
  ) {
    final path = file.path;
    final segments = path.split('/')..removeWhere((segment) => segment.isEmpty);
    final name = segments.isEmpty ? path : segments.last;
    final bytes = _bigIntToInt(file.size);
    return TransferItemViewData(
      name: name,
      path: path,
      size: _formatByteSize(bytes),
      kind: TransferItemKind.file,
      sizeBytes: bytes,
    );
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

  Future<void> _cancelNativeSendTransfer() async {
    try {
      await _sendTransferSource.cancelTransfer();
    } catch (error, stackTrace) {
      debugPrint('cancelTransfer failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _applySendUpdate(
        SendTransferUpdate(
          phase: SendTransferUpdatePhase.failed,
          destinationLabel:
              state.sendDestinationLabel ??
              _formatCodeAsDestination(state.sendDestinationCode),
          statusMessage: 'Cancelling transfer...',
          itemCount: state.sendItems.length,
          totalSize:
              state.sendSummary?.totalSize ?? sampleSendSummary.totalSize,
          bytesSent: state.sendPayloadBytesSent ?? 0,
          totalBytes: state.sendPayloadTotalBytes ?? 0,
          errorMessage: 'Drift couldn\'t cancel the transfer.',
        ),
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

  void _returnToSendSelection() {
    _restoreSendDraft();
  }

  void _restoreSendDraft({String destinationCode = ''}) {
    _cancelActiveSendTransfer();
    _clearSendMetricState();
    _setSession(
      SendDraftSession(
        items: state.sendItems,
        isInspecting: false,
        nearbyDestinations: const [],
        nearbyScanInFlight: false,
        nearbyScanCompletedOnce: false,
        destinationCode: destinationCode,
      ),
    );
    _scheduleNearbyScanning();
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
    unawaited(_runNearbyScanOnce());
    _nearbyScanTimer = Timer.periodic(_nearbyRefreshInterval, (_) {
      final current = _draftSession;
      if (current == null || current.items.isEmpty || current.isInspecting) {
        _cancelNearbyScanTimer();
        return;
      }
      unawaited(_runNearbyScanOnce());
    });
  }

  Future<void> _runNearbyScanOnce() async {
    final draft = _draftSession;
    if (draft == null || draft.isInspecting || draft.nearbyScanInFlight) {
      return;
    }
    _setSession(draft.copyWith(nearbyScanInFlight: true));
    try {
      final next = await _nearbyDiscoverySource.scan(
        timeout: _nearbyScanTimeout,
      );
      final current = _draftSession;
      if (current == null || current.isInspecting) {
        return;
      }
      _setSession(
        current.copyWith(
          nearbyDestinations: List<SendDestinationViewData>.unmodifiable(next),
          nearbyScanInFlight: false,
          nearbyScanCompletedOnce: true,
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('[drift/notifier] nearby scan failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _setSendSetupError('Drift couldn\'t scan for nearby devices right now.');
      final current = _draftSession;
      if (current != null) {
        _setSession(
          current.copyWith(
            nearbyScanInFlight: false,
            nearbyScanCompletedOnce: true,
          ),
        );
      }
    }
  }

  Duration get _nearbyScanTimeout => _identity.deviceType == 'phone'
      ? const Duration(seconds: 4)
      : const Duration(seconds: 8);

  Duration get _nearbyRefreshInterval => _identity.deviceType == 'phone'
      ? const Duration(seconds: 8)
      : const Duration(seconds: 12);

  void _startSendTransferWithTicket(
    SendDestinationViewData destination,
    String ticket,
  ) {
    _cancelNearbyScanTimer();
    _cancelActiveSendTransfer();
    _clearSendMetricState();
    final generation = ++_sendTransferGeneration;
    final request = SendTransferRequestData(
      code: '',
      ticket: ticket,
      lanDestinationLabel: destination.name,
      paths: state.sendItems.map((item) => item.path).toList(growable: false),
      deviceName: state.deviceName,
      deviceType: state.deviceType,
    );
    _listenToSendTransfer(
      generation: generation,
      request: request,
      fallbackDestination: destination.name,
    );
  }

  void _startSendTransfer(String normalizedCode) {
    _cancelNearbyScanTimer();
    _cancelActiveSendTransfer();
    _clearSendMetricState();
    final generation = ++_sendTransferGeneration;
    final request = SendTransferRequestData(
      code: normalizedCode,
      paths: state.sendItems.map((item) => item.path).toList(growable: false),
      deviceName: state.deviceName,
      deviceType: state.deviceType,
      serverUrl: state.serverUrl,
    );
    _listenToSendTransfer(
      generation: generation,
      request: request,
      fallbackDestination: _formatCodeAsDestination(normalizedCode),
    );
  }

  void _listenToSendTransfer({
    required int generation,
    required SendTransferRequestData request,
    required String fallbackDestination,
  }) {
    _sendTransferSubscription = _sendTransferSource
        .startTransfer(request)
        .listen(
          (update) {
            if (generation != _sendTransferGeneration) {
              debugPrint(
                '[drift/notifier] ignoring stale send update '
                'generation=$generation current=$_sendTransferGeneration',
              );
              return;
            }
            _applySendUpdate(update);
          },
          onError: (Object error, StackTrace stackTrace) {
            if (generation != _sendTransferGeneration) {
              return;
            }
            debugPrint('[drift/notifier] failed to send files: $error');
            debugPrintStack(stackTrace: stackTrace);
            _applySendUpdate(
              SendTransferUpdate(
                phase: SendTransferUpdatePhase.failed,
                destinationLabel:
                    state.sendDestinationLabel ?? fallbackDestination,
                statusMessage: 'Request sent',
                itemCount: state.sendItems.length,
                totalSize: sampleSendSummary.totalSize,
                bytesSent: 0,
                totalBytes: 0,
                errorMessage: error.toString(),
              ),
            );
          },
        );
  }

  void _applySendUpdate(SendTransferUpdate update) {
    final items = state.sendItems.isEmpty ? sampleSendItems : state.sendItems;
    final existingSummary = state.sendSummary ?? sampleSendSummary;
    final summary = existingSummary.copyWith(
      itemCount: update.itemCount,
      totalSize: update.totalSize,
      code: state.sendDestinationCode,
      destinationLabel: update.destinationLabel,
      statusMessage: update.errorMessage ?? update.statusMessage,
    );
    final progress = _progressFromSnapshot(update.snapshot);
    final bytesTransferred =
        progress.bytesTransferred ??
        (update.bytesSent > 0 ? update.bytesSent : null);
    if (_sendPayloadStartedAt == null && (bytesTransferred ?? 0) > 0) {
      _sendPayloadStartedAt = DateTime.now();
    }

    switch (update.phase) {
      case SendTransferUpdatePhase.connecting:
        _setSession(
          SendTransferSession(
            phase: SendTransferSessionPhase.connecting,
            items: items,
            summary: summary,
            plan: update.plan ?? state.sendTransferPlan,
            snapshot: update.snapshot,
            remoteDeviceType: update.remoteDeviceType,
          ),
        );
      case SendTransferUpdatePhase.waitingForDecision:
        _setSession(
          SendTransferSession(
            phase: SendTransferSessionPhase.waitingForDecision,
            items: items,
            summary: summary,
            plan: update.plan ?? state.sendTransferPlan,
            snapshot: update.snapshot,
            remoteDeviceType: update.remoteDeviceType,
          ),
        );
      case SendTransferUpdatePhase.accepted:
        _setSession(
          SendTransferSession(
            phase: SendTransferSessionPhase.accepted,
            items: items,
            summary: summary,
            plan: update.plan ?? state.sendTransferPlan,
            snapshot: update.snapshot,
            remoteDeviceType: update.remoteDeviceType,
          ),
        );
      case SendTransferUpdatePhase.declined:
        _setSession(
          SendResultSession(
            success: false,
            outcome: TransferResultOutcomeData.declined,
            items: items,
            summary: summary.copyWith(
              statusMessage: update.errorMessage ?? 'Transfer declined.',
            ),
            plan: update.plan ?? state.sendTransferPlan,
            snapshot: update.snapshot,
            remoteDeviceType: update.remoteDeviceType,
          ),
        );
      case SendTransferUpdatePhase.sending:
        final payloadBytesSent = bytesTransferred;
        final payloadTotalBytes =
            progress.totalBytes ??
            (update.totalBytes > 0 ? update.totalBytes : null);
        _setSession(
          SendTransferSession(
            phase: SendTransferSessionPhase.sending,
            items: items,
            summary: summary,
            plan: update.plan ?? state.sendTransferPlan,
            snapshot: update.snapshot,
            remoteDeviceType: update.remoteDeviceType,
            payloadBytesSent: payloadBytesSent,
            payloadTotalBytes: payloadTotalBytes,
            payloadSpeedLabel: progress.speedLabel,
            payloadEtaLabel: progress.etaLabel,
          ),
        );
      case SendTransferUpdatePhase.completed:
        _setSession(
          SendResultSession(
            success: true,
            outcome: TransferResultOutcomeData.success,
            items: items,
            summary: summary,
            metrics: _buildSendCompletionMetrics(
              update,
              payloadStartedAt: _sendPayloadStartedAt,
            ),
            plan: update.plan ?? state.sendTransferPlan,
            snapshot: update.snapshot,
            remoteDeviceType: update.remoteDeviceType,
          ),
        );
      case SendTransferUpdatePhase.cancelled:
        _setSession(
          SendResultSession(
            success: false,
            outcome: TransferResultOutcomeData.cancelled,
            items: items,
            summary: summary.copyWith(
              statusMessage: update.errorMessage ?? 'Transfer cancelled.',
            ),
            plan: update.plan ?? state.sendTransferPlan,
            snapshot: update.snapshot,
            remoteDeviceType: update.remoteDeviceType,
          ),
        );
      case SendTransferUpdatePhase.failed:
        _setSession(
          SendResultSession(
            success: false,
            outcome: TransferResultOutcomeData.failed,
            items: items,
            summary: summary,
            plan: update.plan ?? state.sendTransferPlan,
            snapshot: update.snapshot,
            remoteDeviceType: update.remoteDeviceType,
          ),
        );
    }
  }

  _TransferProgressMetrics _progressFromSnapshot(
    rust_transfer.TransferSnapshotData? snapshot,
  ) {
    if (snapshot == null) {
      return const _TransferProgressMetrics();
    }

    final bytesTransferred = _bigIntToInt(snapshot.bytesTransferred);
    final totalBytes = _bigIntToInt(snapshot.totalBytes);
    final bytesPerSec = snapshot.bytesPerSec == null
        ? null
        : _bigIntToInt(snapshot.bytesPerSec!);
    final etaSeconds = snapshot.etaSeconds == null
        ? null
        : _bigIntToInt(snapshot.etaSeconds!);

    return _TransferProgressMetrics(
      bytesTransferred: bytesTransferred,
      totalBytes: totalBytes,
      speedLabel: bytesPerSec != null && bytesPerSec >= 16
          ? _formatBytesPerSecond(bytesPerSec.toDouble())
          : null,
      etaLabel: etaSeconds != null && etaSeconds > 0
          ? _formatEtaSeconds(etaSeconds.toDouble())
          : null,
    );
  }

  List<TransferMetricRow> _buildPerformanceMetrics({
    required DateTime? startedAt,
    required int bytesTransferred,
  }) {
    final rows = <TransferMetricRow>[];
    if (startedAt == null) {
      return rows;
    }

    final now = DateTime.now();
    final transferElapsed = now.difference(startedAt);
    if (transferElapsed.inMilliseconds >= 200) {
      rows.add(
        TransferMetricRow(
          label: 'Transfer time',
          value: _formatElapsedDuration(transferElapsed),
        ),
      );
    }

    final payloadSec = transferElapsed.inMilliseconds / 1000.0;
    if (payloadSec >= 0.25 && bytesTransferred > 0) {
      rows.add(
        TransferMetricRow(
          label: 'Average speed',
          value: _formatBytesPerSecond(bytesTransferred / payloadSec),
        ),
      );
    }

    return rows;
  }

  List<TransferMetricRow>? _buildSendCompletionMetrics(
    SendTransferUpdate update, {
    required DateTime? payloadStartedAt,
  }) {
    final rows = <TransferMetricRow>[];
    final recipient = update.destinationLabel.trim().isEmpty
        ? 'Recipient device'
        : update.destinationLabel;
    rows.add(TransferMetricRow(label: 'Sent to', value: recipient));
    rows.add(TransferMetricRow(label: 'Files', value: '${update.itemCount}'));
    rows.add(TransferMetricRow(label: 'Size', value: update.totalSize));
    rows.addAll(
      _buildPerformanceMetrics(
        startedAt: payloadStartedAt,
        bytesTransferred: update.bytesSent,
      ),
    );
    return rows;
  }

  List<TransferMetricRow>? _buildReceiveCompletionMetrics({
    required TransferSummaryViewData summary,
    required int bytesReceived,
  }) {
    final rows = <TransferMetricRow>[];
    if (summary.senderName.isNotEmpty) {
      rows.add(TransferMetricRow(label: 'From', value: summary.senderName));
    }
    rows.add(
      TransferMetricRow(label: 'Saved to', value: summary.destinationLabel),
    );
    rows.add(TransferMetricRow(label: 'Files', value: '${summary.itemCount}'));
    rows.add(TransferMetricRow(label: 'Size', value: summary.totalSize));
    rows.addAll(
      _buildPerformanceMetrics(
        startedAt: _receivePayloadStartedAt,
        bytesTransferred: bytesReceived,
      ),
    );
    return rows;
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

  void _cancelActiveSendTransfer() {
    _sendTransferGeneration += 1;
    unawaited(_sendTransferSubscription?.cancel());
    _sendTransferSubscription = null;
  }

  void _cancelNearbyScanTimer() {
    _nearbyScanTimer?.cancel();
    _nearbyScanTimer = null;
  }

  SendDraftSession? get _draftSession {
    final session = state.session;
    return session is SendDraftSession ? session : null;
  }

  List<String> get _currentSendSelectionPaths =>
      state.sendItems.map((item) => item.path).toList(growable: false);

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

  void _clearSendMetricState() {
    _sendPayloadStartedAt = null;
  }

  void _clearReceiveMetricState() {
    _receivePayloadStartedAt = null;
  }

  void _dispose() {
    _cancelNearbyScanTimer();
    _sendTransferSubscription?.cancel();
    _badgeSubscription?.cancel();
    _incomingSubscription?.cancel();
  }
}

class _TransferProgressMetrics {
  const _TransferProgressMetrics({
    this.bytesTransferred,
    this.totalBytes,
    this.speedLabel,
    this.etaLabel,
  });

  final int? bytesTransferred;
  final int? totalBytes;
  final String? speedLabel;
  final String? etaLabel;
}

int _bigIntToInt(BigInt value) {
  if (value.bitLength > 63) {
    return 0x7fffffffffffffff;
  }
  return value.toInt();
}

String _formatCodeAsDestination(String code) {
  final prefix = code.substring(0, 3);
  final suffix = code.substring(3);
  return 'Code $prefix $suffix';
}

String _formatElapsedDuration(Duration duration) {
  final ms = duration.inMilliseconds;
  if (ms < 60 * 1000) {
    final sec = (ms / 1000).clamp(0.05, double.infinity);
    if (sec < 10) {
      return '${sec.toStringAsFixed(1)} s';
    }
    return '${sec.round()} s';
  }
  if (ms < 3600 * 1000) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return seconds == 0 ? '$minutes min' : '$minutes min $seconds s';
  }
  final hours = duration.inHours;
  final minutes = duration.inMinutes % 60;
  return minutes == 0 ? '$hours h' : '$hours h $minutes min';
}

String _formatBytesPerSecond(double bps) {
  const units = ['B/s', 'KB/s', 'MB/s', 'GB/s'];
  var value = bps;
  var index = 0;
  while (value >= 1024 && index < units.length - 1) {
    value /= 1024;
    index += 1;
  }
  final decimals = value >= 10 || index == 0 ? 0 : 1;
  return '${value.toStringAsFixed(decimals)} ${units[index]}';
}

String _formatEtaSeconds(double seconds) {
  if (seconds.isNaN || seconds.isInfinite || seconds <= 0) {
    return '';
  }
  if (seconds < 1) {
    return 'Finishing…';
  }
  if (seconds < 45) {
    return '${seconds.round()}s';
  }
  if (seconds < 3600) {
    final minutes = (seconds / 60).ceil();
    return minutes <= 1 ? '1 min' : '$minutes min';
  }
  final hours = (seconds / 3600).ceil();
  return hours <= 1 ? '1 h' : '$hours h';
}

String _formatByteSize(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  final decimals = value >= 10 || unitIndex == 0 ? 0 : 1;
  return '${value.toStringAsFixed(decimals)} ${units[unitIndex]}';
}

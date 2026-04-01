import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/transfer_models.dart';
import '../platform/app_focus.dart';
import '../platform/send_item_source.dart';
import '../platform/send_transfer_source.dart';
import '../src/rust/api/receiver.dart' as rust_receiver;
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
  DateTime? _lastSendProgressSampleAt;
  int? _lastSendProgressBytes;
  double? _sendSmoothedBps;
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
    switch (mode) {
      case TransferDirection.send:
        resetShell();
      case TransferDirection.receive:
        openReceivePanel();
    }
  }

  void openReceivePanel() {
    _cancelNearbyScanTimer();
    if (state.session is ReceiveIdleSession ||
        state.session is ReceiveOfferSession ||
        state.session is ReceiveTransferSession ||
        state.session is ReceiveResultSession) {
      return;
    }
    _setSession(const ReceiveIdleSession());
  }

  void closeReceivePanel() {
    _setSession(const IdleSession());
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
    _setSession(draft.copyWith(destinationCode: normalized));
    if (normalized.length == 6 &&
        draft.items.isNotEmpty &&
        !draft.isInspecting) {
      _startSendTransfer(normalized);
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
          items: session.items,
          summary: session.summary.copyWith(
            statusMessage: 'Saved to ${session.summary.destinationLabel}',
          ),
        ),
      );
      return;
    }

    _receivePayloadStartedAt = null;
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
      _setSession(const ReceiveIdleSession());
      unawaited(_respondToIncomingOffer(accept: false));
      return;
    }
    closeReceivePanel();
  }

  void cancelSendInProgress() {
    if (state.session is! SendTransferSession) {
      return;
    }
    _returnToSendSelection();
  }

  void resetShell() {
    _cancelNearbyScanTimer();
    _cancelActiveSendTransfer();
    _setSession(const IdleSession());
  }

  void goBack() {
    switch (state.session) {
      case ReceiveOfferSession(:final decisionPending):
        if (decisionPending) {
          unawaited(_respondToIncomingOffer(accept: false));
        }
        _setSession(const ReceiveIdleSession());
      case ReceiveResultSession():
        _setSession(const ReceiveIdleSession());
      case ReceiveIdleSession():
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
    final ticket = destination.lanTicket?.trim();
    if (draft == null ||
        ticket == null ||
        ticket.isEmpty ||
        !state.canBrowseNearbyReceivers) {
      return;
    }
    _startSendTransferWithTicket(destination, ticket);
  }

  Future<void> _pickSendItems() async {
    _beginSendInspection(clearExistingItems: true);
    try {
      final items = await _sendItemSource.pickFiles();
      if (items.isEmpty) {
        clearSendFlow();
        return;
      }
      _applySelectedSendItems(items);
    } catch (error, stackTrace) {
      clearSendFlow();
      _reportSendSelectionError(error, stackTrace);
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
      _applySelectedSendItems(items);
    } catch (error, stackTrace) {
      clearSendFlow();
      _reportSendSelectionError(error, stackTrace);
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
      _applySelectedSendItems(items);
    } catch (error, stackTrace) {
      _finishSendInspection();
      _reportSendSelectionError(error, stackTrace);
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
      _applySelectedSendItems(items);
    } catch (error, stackTrace) {
      _finishSendInspection();
      _reportSendSelectionError(error, stackTrace);
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
      _applySelectedSendItems(items);
    } catch (error, stackTrace) {
      _finishSendInspection();
      _reportSendSelectionError(error, stackTrace);
    }
  }

  void _applySelectedSendItems(List<TransferItemViewData> items) {
    _cancelActiveSendTransfer();
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
            resetShell();
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
      case rust_receiver.ReceiverTransferPhase.failed:
        debugPrint(
          '[drift/notifier] incoming receive failed: '
          '${event.errorMessage ?? event.statusMessage}',
        );
        resetShell();
        return;
      case rust_receiver.ReceiverTransferPhase.declined:
        _setSession(const ReceiveIdleSession());
        return;
    }
  }

  void _applyIncomingOffer(rust_receiver.ReceiverTransferEvent event) {
    final items = List<TransferItemViewData>.unmodifiable(
      event.files.map(_incomingFileToViewData),
    );
    _cancelActiveSendTransfer();
    _receivePayloadStartedAt = null;
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
        senderDeviceType: event.senderDeviceType,
      ),
    );
    unawaited(focusAppForIncomingTransfer());
  }

  void _applyIncomingReceiving(rust_receiver.ReceiverTransferEvent event) {
    final payloadBytesReceived = _bigIntToInt(event.totalSizeBytes);
    if (_receivePayloadStartedAt == null && payloadBytesReceived > 0) {
      _receivePayloadStartedAt = DateTime.now();
    }
    final payloadTotalBytes =
        state.receivePayloadTotalBytes ?? payloadBytesReceived;

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
        payloadBytesReceived: payloadBytesReceived,
        payloadTotalBytes: payloadTotalBytes,
        senderDeviceType: event.senderDeviceType,
      ),
    );
  }

  void _applyIncomingCompleted(rust_receiver.ReceiverTransferEvent event) {
    final bytesReceived = _bigIntToInt(event.totalSizeBytes);
    final totalBytes = state.receivePayloadTotalBytes ?? bytesReceived;
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
        items: state.receiveItems,
        summary: completedSummary,
        metrics: _buildReceiveCompletionMetrics(
          summary: completedSummary,
          bytesReceived: bytesReceived,
        ),
        payloadBytesReceived: bytesReceived,
        payloadTotalBytes: totalBytes,
        senderDeviceType: event.senderDeviceType,
      ),
    );
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
      resetShell();
    }
  }

  void _returnToSendSelection() {
    _cancelActiveSendTransfer();
    _clearSendMetricState();
    _setSession(
      SendDraftSession(
        items: state.sendItems,
        isInspecting: false,
        nearbyDestinations: const [],
        nearbyScanInFlight: false,
        nearbyScanCompletedOnce: false,
        destinationCode: '',
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
    final payloadStartedAt = _sendPayloadStartedAt;
    final summary = existingSummary.copyWith(
      itemCount: update.itemCount,
      totalSize: update.totalSize,
      code: state.sendDestinationCode,
      destinationLabel: update.destinationLabel,
      statusMessage: update.errorMessage ?? update.statusMessage,
    );
    final progress = _updateSendTransferMetrics(update);

    switch (update.phase) {
      case SendTransferUpdatePhase.connecting:
        _setSession(
          SendTransferSession(
            phase: SendTransferSessionPhase.connecting,
            items: items,
            summary: summary,
            remoteDeviceType: update.remoteDeviceType,
          ),
        );
      case SendTransferUpdatePhase.waitingForDecision:
        _setSession(
          SendTransferSession(
            phase: SendTransferSessionPhase.waitingForDecision,
            items: items,
            summary: summary,
            remoteDeviceType: update.remoteDeviceType,
          ),
        );
      case SendTransferUpdatePhase.sending:
        _setSession(
          SendTransferSession(
            phase: SendTransferSessionPhase.sending,
            items: items,
            summary: summary,
            remoteDeviceType: update.remoteDeviceType,
            payloadBytesSent: progress.bytesSent,
            payloadTotalBytes: progress.totalBytes,
            payloadSpeedLabel: progress.speedLabel,
            payloadEtaLabel: progress.etaLabel,
          ),
        );
      case SendTransferUpdatePhase.completed:
        _setSession(
          SendResultSession(
            success: true,
            items: items,
            summary: summary,
            metrics: _buildSendCompletionMetrics(
              update,
              payloadStartedAt: payloadStartedAt,
            ),
            remoteDeviceType: update.remoteDeviceType,
          ),
        );
      case SendTransferUpdatePhase.failed:
        _setSession(
          SendResultSession(
            success: false,
            items: items,
            summary: summary,
            remoteDeviceType: update.remoteDeviceType,
          ),
        );
    }
  }

  _SendTransferProgress _updateSendTransferMetrics(SendTransferUpdate update) {
    switch (update.phase) {
      case SendTransferUpdatePhase.connecting:
      case SendTransferUpdatePhase.waitingForDecision:
        _clearSendMetricState();
        return const _SendTransferProgress();
      case SendTransferUpdatePhase.sending:
        _sendPayloadStartedAt ??= DateTime.now();
        final now = DateTime.now();
        final prevAt = _lastSendProgressSampleAt;
        final prevBytes = _lastSendProgressBytes;
        if (prevAt != null && prevBytes != null) {
          final dtSec = now.difference(prevAt).inMicroseconds / 1e6;
          final dBytes = update.bytesSent - prevBytes;
          if (dtSec >= 0.08 && dBytes >= 0) {
            final inst = dBytes / dtSec;
            final prev = _sendSmoothedBps;
            _sendSmoothedBps = prev == null ? inst : 0.22 * inst + 0.78 * prev;
          }
        }
        _lastSendProgressSampleAt = now;
        _lastSendProgressBytes = update.bytesSent;

        String? speedLabel;
        String? etaLabel;
        final bps = _sendSmoothedBps;
        if (bps != null && bps >= 16) {
          speedLabel = _formatBytesPerSecond(bps);
          final left = (update.totalBytes - update.bytesSent).clamp(
            0,
            update.totalBytes,
          );
          etaLabel = left <= 0 ? null : _formatEtaSeconds(left / bps);
        }

        return _SendTransferProgress(
          bytesSent: update.bytesSent,
          totalBytes: update.totalBytes,
          speedLabel: speedLabel,
          etaLabel: etaLabel,
        );
      case SendTransferUpdatePhase.completed:
      case SendTransferUpdatePhase.failed:
        _clearSendMetricState();
        return const _SendTransferProgress();
    }
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

  void _reportSendSelectionError(Object error, StackTrace stackTrace) {
    debugPrint('Failed to inspect selected send items: $error');
    debugPrintStack(stackTrace: stackTrace);
  }

  void _clearSendMetricState() {
    _sendPayloadStartedAt = null;
    _lastSendProgressSampleAt = null;
    _lastSendProgressBytes = null;
    _sendSmoothedBps = null;
  }

  void _dispose() {
    _cancelNearbyScanTimer();
    _sendTransferSubscription?.cancel();
    _badgeSubscription?.cancel();
    _incomingSubscription?.cancel();
  }
}

class _SendTransferProgress {
  const _SendTransferProgress({
    this.bytesSent,
    this.totalBytes,
    this.speedLabel,
    this.etaLabel,
  });

  final int? bytesSent;
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
  if (seconds < 45) {
    return 'About ${seconds.round()} s left';
  }
  if (seconds < 3600) {
    final minutes = (seconds / 60).ceil();
    return minutes <= 1 ? 'About 1 min left' : 'About $minutes min left';
  }
  final hours = (seconds / 3600).ceil();
  return hours <= 1 ? 'About 1 h left' : 'About $hours h left';
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

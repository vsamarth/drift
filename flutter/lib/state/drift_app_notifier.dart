import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/transfer_models.dart';
import '../platform/app_focus.dart';
import '../features/receive/receive_mapper.dart';
import '../src/rust/api/receiver.dart' as rust_receiver;
import '../features/settings/settings_state.dart';
import '../features/settings/settings_providers.dart';
import 'app_identity.dart';
import 'drift_dependencies.dart';
import 'drift_app_state.dart';
import 'receiver_service_source.dart';

class DriftAppNotifier extends Notifier<DriftAppState>
{
  late DriftAppIdentity _identity;
  late final ReceiverServiceSource _receiverServiceSource;
  late final bool _animateSendingConnection;
  late final bool _enableIdleIncomingListener;

  StreamSubscription<ReceiverBadgeState>? _badgeSubscription;
  StreamSubscription<rust_receiver.ReceiverTransferEvent>?
  _incomingSubscription;
  bool? _appliedDiscoverable;

  DateTime? _receivePayloadStartedAt;

  @override
  DriftAppState build() {
    _identity = ref.watch(initialDriftAppIdentityProvider);
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
    _clearReceiveMetricState();
    _setSession(const IdleSession());
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

  void _setSession(ShellSessionState session) {
    state = state.copyWith(session: session);
    _syncSessionPolicies();
  }

  void _syncSessionPolicies() {
    unawaited(_syncDiscoverabilityPolicy());
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

  void _clearReceiveMetricState() {
    _receivePayloadStartedAt = null;
  }

  void _dispose() {
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

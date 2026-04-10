import '../../core/models/transfer_models.dart';
import '../../shared/formatting/byte_format.dart';
import '../../state/app_identity.dart';
import '../../state/drift_app_state.dart';
import 'send_flow_state.dart';
import '../../src/rust/api/transfer.dart' as rust_transfer;

class SendState {
  const SendState(this.appState, this.sendSetupErrorMessage);

  factory SendState.fromAppState(
    DriftAppState state, {
    String? sendSetupErrorMessage,
  }) {
    return SendState(state, sendSetupErrorMessage);
  }

  final DriftAppState appState;
  final String? sendSetupErrorMessage;

  DriftAppIdentity get identity => appState.identity;
  bool get animateSendingConnection => appState.animateSendingConnection;
  TransferDirection get mode => appState.mode;
  ShellSessionState get session => appState.session;
  TransferStage get sendStage => switch (session) {
    SendDraftSession() => TransferStage.collecting,
    SendTransferSession(:final phase) => switch (phase) {
      SendTransferSessionPhase.connecting => TransferStage.ready,
      SendTransferSessionPhase.waitingForDecision ||
      SendTransferSessionPhase.accepted ||
      SendTransferSessionPhase.declined ||
      SendTransferSessionPhase.sending => TransferStage.waiting,
      SendTransferSessionPhase.cancelling => TransferStage.waiting,
    },
    SendResultSession(:final success) =>
      success ? TransferStage.completed : TransferStage.error,
    _ => TransferStage.idle,
  };
  String get deviceName => appState.deviceName;
  String get deviceType => appState.deviceType;
  String get sendDestinationCode => switch (session) {
    SendDraftSession(:final destinationCode) => destinationCode,
    SendTransferSession(:final summary) => summary.code,
    SendResultSession(:final summary) => summary.code,
    _ => '',
  };
  String? get sendDestinationLabel => switch (session) {
    SendTransferSession(:final summary) => summary.destinationLabel,
    SendResultSession(:final summary) => summary.destinationLabel,
    _ => null,
  };
  String? get sendRemoteDeviceType => switch (session) {
    SendTransferSession(:final remoteDeviceType) => remoteDeviceType,
    SendResultSession(:final remoteDeviceType) => remoteDeviceType,
    _ => null,
  };
  List<TransferItemViewData> get sendItems => switch (session) {
    SendDraftSession(:final items) => items,
    SendTransferSession(:final items) => items,
    SendResultSession(:final items) => items,
    _ => const [],
  };
  List<TransferDisplayItemViewData> get sendDisplayItems =>
      _displayItemsFor(sendItems, sendTransferPlan, sendTransferSnapshot);
  List<TransferDisplayItemViewData> get receiveDisplayItems =>
      appState.receiveDisplayItems;
  List<SendDestinationViewData> get nearbySendDestinations => switch (session) {
    SendDraftSession(:final nearbyDestinations) => nearbyDestinations,
    _ => const [],
  };
  SendDestinationViewData? get selectedSendDestination => switch (session) {
    SendDraftSession(:final selectedDestination) => selectedDestination,
    _ => null,
  };
  TransferSummaryViewData? get sendSummary => switch (session) {
    SendTransferSession(:final summary) => summary,
    SendResultSession(:final summary) => summary,
    _ => null,
  };
  int? get sendPayloadBytesSent => switch (session) {
    SendTransferSession(:final payloadBytesSent) => payloadBytesSent,
    _ => null,
  };
  int? get sendPayloadTotalBytes => switch (session) {
    SendTransferSession(:final payloadTotalBytes) => payloadTotalBytes,
    _ => null,
  };
  String? get sendTransferSpeedLabel => switch (session) {
    SendTransferSession(:final payloadSpeedLabel) => payloadSpeedLabel,
    _ => null,
  };
  String? get sendTransferEtaLabel => switch (session) {
    SendTransferSession(:final payloadEtaLabel) => payloadEtaLabel,
    _ => null,
  };
  bool get hasSendPayloadProgress =>
      sendPayloadBytesSent != null &&
      sendPayloadTotalBytes != null &&
      sendPayloadTotalBytes! > 0;
  List<TransferMetricRow>? get sendCompletionMetrics => switch (session) {
    SendResultSession(:final metrics) => metrics,
    _ => null,
  };
  rust_transfer.TransferPlanData? get sendTransferPlan => switch (session) {
    SendTransferSession(:final plan) => plan,
    SendResultSession(:final plan) => plan,
    _ => null,
  };
  rust_transfer.TransferSnapshotData? get sendTransferSnapshot =>
      switch (session) {
        SendTransferSession(:final snapshot) => snapshot,
        SendResultSession(:final snapshot) => snapshot,
        _ => null,
      };
  bool get canBrowseNearbyReceivers =>
      session is SendDraftSession &&
      sendItems.isNotEmpty &&
      !isInspectingSendItems;
  bool get nearbyScanInProgress =>
      session is SendDraftSession &&
      (session as SendDraftSession).nearbyScanInFlight;
  bool get nearbyScanHasCompletedOnce =>
      session is SendDraftSession &&
      (session as SendDraftSession).nearbyScanCompletedOnce;
  bool get isInspectingSendItems =>
      session is SendDraftSession && (session as SendDraftSession).isInspecting;
  TransferResultViewData? get transferResult => switch (session) {
    SendResultSession(:final outcome, :final summary, :final metrics) =>
      buildSendTransferResultViewData(
        outcome: outcome,
        summary: summary,
        metrics: metrics,
      ),
    _ => null,
  };
  bool get discoverableEnabled =>
      appState.discoverableByDefault && (session is IdleSession);
}

List<TransferDisplayItemViewData> _displayItemsFor(
  List<TransferItemViewData> fallbackItems,
  rust_transfer.TransferPlanData? plan,
  rust_transfer.TransferSnapshotData? snapshot,
) {
  if (plan == null) {
    return plainTransferDisplayItems(fallbackItems);
  }

  return List<TransferDisplayItemViewData>.unmodifiable(
    plan.files.map((file) {
      final item = TransferItemViewData(
        name: _fileNameFromPath(file.path),
        path: file.path,
        size: formatBytes(_bigIntToInt(file.size)),
        kind: TransferItemKind.file,
        sizeBytes: _bigIntToInt(file.size),
      );

      if (snapshot == null) {
        return TransferDisplayItemViewData(
          item: item,
          state: TransferItemProgressState.pending,
        );
      }

      final isCompleted = file.id < snapshot.completedFiles;
      if (isCompleted) {
        return TransferDisplayItemViewData(
          item: item,
          state: TransferItemProgressState.completed,
          progress: 1,
          statusLabel: 'Done',
        );
      }

      final isActive = snapshot.activeFileId == file.id;
      if (isActive) {
        final transferred = snapshot.activeFileBytes == null
            ? 0
            : _bigIntToInt(snapshot.activeFileBytes!);
        final total = _bigIntToInt(file.size);
        return TransferDisplayItemViewData(
          item: item,
          state: TransferItemProgressState.active,
          progress: total <= 0 ? 1.0 : (transferred / total).clamp(0.0, 1.0),
          statusLabel: total <= 0
              ? 'Preparing'
              : '${formatBytes(transferred)} / ${formatBytes(total)}',
        );
      }

      return TransferDisplayItemViewData(
        item: item,
        state: TransferItemProgressState.pending,
      );
    }),
  );
}

String _fileNameFromPath(String path) {
  final segments = path.split('/')..removeWhere((segment) => segment.isEmpty);
  return segments.isEmpty ? path : segments.last;
}

int _bigIntToInt(BigInt value) {
  if (value.bitLength > 63) {
    return 0x7fffffffffffffff;
  }
  return value.toInt();
}

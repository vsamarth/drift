import 'package:flutter/foundation.dart';

import '../core/models/transfer_models.dart';
import '../shared/formatting/byte_format.dart';
import '../src/rust/api/transfer.dart' as rust_transfer;
import 'app_identity.dart';
import 'receiver_service_source.dart';
import 'shell_session_state.dart';
import 'transfer_result_state.dart';

export 'shell_session_state.dart';
export 'transfer_result_state.dart';
export '../features/send/send_flow_state.dart';

@immutable
class DriftAppState {
  const DriftAppState({
    required this.identity,
    required this.receiverBadge,
    required this.session,
    required this.animateSendingConnection,
    this.sendSetupErrorMessage,
  });

  final DriftAppIdentity identity;
  final ReceiverBadgeState receiverBadge;
  final ShellSessionState session;
  final bool animateSendingConnection;
  final String? sendSetupErrorMessage;

  DriftAppState copyWith({
    DriftAppIdentity? identity,
    ReceiverBadgeState? receiverBadge,
    ShellSessionState? session,
    bool? animateSendingConnection,
    String? sendSetupErrorMessage,
    bool clearSendSetupErrorMessage = false,
  }) {
    return DriftAppState(
      identity: identity ?? this.identity,
      receiverBadge: receiverBadge ?? this.receiverBadge,
      session: session ?? this.session,
      animateSendingConnection:
          animateSendingConnection ?? this.animateSendingConnection,
      sendSetupErrorMessage: clearSendSetupErrorMessage
          ? null
          : (sendSetupErrorMessage ?? this.sendSetupErrorMessage),
    );
  }

  String get deviceName => identity.deviceName;
  String get deviceType => identity.deviceType;
  String get downloadRoot => identity.downloadRoot;
  String? get serverUrl => identity.serverUrl;
  bool get discoverableByDefault => identity.discoverableByDefault;
  String get idleReceiveCode => receiverBadge.code;
  String get idleReceiveStatus => receiverBadge.status;

  TransferDirection get mode => switch (session) {
    ReceiveOfferSession() ||
    ReceiveTransferSession() ||
    ReceiveResultSession() => TransferDirection.receive,
    _ => TransferDirection.send,
  };

  TransferStage get receiveStage => switch (session) {
    ReceiveOfferSession() => TransferStage.review,
    ReceiveTransferSession() => TransferStage.waiting,
    ReceiveResultSession() => TransferStage.completed,
    _ => TransferStage.idle,
  };

  String? get receiveSenderDeviceType => switch (session) {
    ReceiveOfferSession(:final senderDeviceType)
        when senderDeviceType?.trim().isNotEmpty == true =>
      senderDeviceType,
    ReceiveTransferSession(:final senderDeviceType)
        when senderDeviceType?.trim().isNotEmpty == true =>
      senderDeviceType,
    ReceiveResultSession(:final senderDeviceType)
        when senderDeviceType?.trim().isNotEmpty == true =>
      senderDeviceType,
    _ => null,
  };

  String get receiveCode => switch (session) {
    ReceiveOfferSession(:final summary) => summary.code,
    ReceiveTransferSession(:final summary) => summary.code,
    ReceiveResultSession(:final summary) => summary.code,
    _ => '',
  };

  List<TransferItemViewData> get receiveItems => switch (session) {
    ReceiveOfferSession(:final items) => items,
    ReceiveTransferSession(:final items) => items,
    ReceiveResultSession(:final items) => items,
    _ => const [],
  };

  List<TransferDisplayItemViewData> get receiveDisplayItems => _displayItemsFor(
    receiveItems,
    receiveTransferPlan,
    receiveTransferSnapshot,
  );

  TransferSummaryViewData? get receiveSummary => switch (session) {
    ReceiveOfferSession(:final summary) => summary,
    ReceiveTransferSession(:final summary) => summary,
    ReceiveResultSession(:final summary) => summary,
    _ => null,
  };

  int? get receivePayloadBytesReceived => switch (session) {
    ReceiveTransferSession(:final payloadBytesReceived) => payloadBytesReceived,
    ReceiveResultSession(:final payloadBytesReceived) => payloadBytesReceived,
    _ => null,
  };

  int? get receivePayloadTotalBytes => switch (session) {
    ReceiveOfferSession(:final payloadTotalBytes) => payloadTotalBytes,
    ReceiveTransferSession(:final payloadTotalBytes) => payloadTotalBytes,
    ReceiveResultSession(:final payloadTotalBytes) => payloadTotalBytes,
    _ => null,
  };

  String? get receiveTransferSpeedLabel => switch (session) {
    ReceiveTransferSession(:final payloadSpeedLabel) => payloadSpeedLabel,
    _ => null,
  };

  String? get receiveTransferEtaLabel => switch (session) {
    ReceiveTransferSession(:final payloadEtaLabel) => payloadEtaLabel,
    _ => null,
  };

  bool get hasReceivePayloadProgress =>
      receivePayloadBytesReceived != null &&
      receivePayloadTotalBytes != null &&
      receivePayloadTotalBytes! > 0;

  List<TransferMetricRow>? get receiveCompletionMetrics => switch (session) {
    ReceiveResultSession(:final metrics) => metrics,
    _ => null,
  };

  rust_transfer.TransferPlanData? get receiveTransferPlan => switch (session) {
    ReceiveOfferSession(:final plan) => plan,
    ReceiveTransferSession(:final plan) => plan,
    ReceiveResultSession(:final plan) => plan,
    _ => null,
  };

  rust_transfer.TransferSnapshotData? get receiveTransferSnapshot =>
      switch (session) {
        ReceiveOfferSession(:final snapshot) => snapshot,
    ReceiveTransferSession(:final snapshot) => snapshot,
    ReceiveResultSession(:final snapshot) => snapshot,
    _ => null,
  };

  TransferResultViewData? get transferResult => switch (session) {
    ReceiveResultSession(:final outcome, :final summary, :final metrics) =>
      buildReceiveTransferResultViewData(
        outcome: outcome,
        summary: summary,
        metrics: metrics,
      ),
    _ => null,
  };

  bool get hasActiveTransfer => session is! IdleSession;

  bool get discoverableEnabled =>
      discoverableByDefault && (session is IdleSession);
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

class ReceiveOfferSession extends ShellSessionState {
  const ReceiveOfferSession({
    required this.items,
    required this.summary,
    required this.decisionPending,
    required this.payloadTotalBytes,
    this.plan,
    this.snapshot,
    this.senderDeviceType,
  });

  final List<TransferItemViewData> items;
  final TransferSummaryViewData summary;
  final bool decisionPending;
  final int? payloadTotalBytes;
  final rust_transfer.TransferPlanData? plan;
  final rust_transfer.TransferSnapshotData? snapshot;
  final String? senderDeviceType;
}

class ReceiveTransferSession extends ShellSessionState {
  const ReceiveTransferSession({
    required this.items,
    required this.summary,
    this.plan,
    this.snapshot,
    this.payloadBytesReceived,
    this.payloadTotalBytes,
    this.payloadSpeedLabel,
    this.payloadEtaLabel,
    this.senderDeviceType,
  });

  final List<TransferItemViewData> items;
  final TransferSummaryViewData summary;
  final rust_transfer.TransferPlanData? plan;
  final rust_transfer.TransferSnapshotData? snapshot;
  final int? payloadBytesReceived;
  final int? payloadTotalBytes;
  final String? payloadSpeedLabel;
  final String? payloadEtaLabel;
  final String? senderDeviceType;

  ReceiveTransferSession copyWith({
    List<TransferItemViewData>? items,
    TransferSummaryViewData? summary,
    rust_transfer.TransferPlanData? plan,
    rust_transfer.TransferSnapshotData? snapshot,
    int? payloadBytesReceived,
    int? payloadTotalBytes,
    String? payloadSpeedLabel,
    String? payloadEtaLabel,
    String? senderDeviceType,
  }) {
    return ReceiveTransferSession(
      items: items ?? this.items,
      summary: summary ?? this.summary,
      plan: plan ?? this.plan,
      snapshot: snapshot ?? this.snapshot,
      payloadBytesReceived: payloadBytesReceived ?? this.payloadBytesReceived,
      payloadTotalBytes: payloadTotalBytes ?? this.payloadTotalBytes,
      payloadSpeedLabel: payloadSpeedLabel ?? this.payloadSpeedLabel,
      payloadEtaLabel: payloadEtaLabel ?? this.payloadEtaLabel,
      senderDeviceType: senderDeviceType ?? this.senderDeviceType,
    );
  }
}

class ReceiveResultSession extends TransferResultSession {
  const ReceiveResultSession({
    required this.success,
    required this.outcome,
    required super.items,
    required super.summary,
    super.metrics,
    super.plan,
    super.snapshot,
    this.payloadBytesReceived,
    this.payloadTotalBytes,
    this.senderDeviceType,
  }) : super();

  final bool success;
  final TransferResultOutcomeData outcome;
  final int? payloadBytesReceived;
  final int? payloadTotalBytes;
  final String? senderDeviceType;
}

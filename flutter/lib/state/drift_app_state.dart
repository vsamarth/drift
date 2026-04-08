import 'package:flutter/foundation.dart';

import '../core/models/transfer_models.dart';
import '../shell/shell_routing.dart';
import '../src/rust/api/transfer.dart' as rust_transfer;
import 'app_identity.dart';
import 'receiver_service_source.dart';

enum TransferResultToneData { success, error }

@immutable
class TransferResultViewData {
  const TransferResultViewData({
    required this.tone,
    required this.title,
    required this.message,
    this.metrics,
    this.primaryLabel,
  });

  final TransferResultToneData tone;
  final String title;
  final String message;
  final List<TransferMetricRow>? metrics;
  final String? primaryLabel;
}

@immutable
class DriftAppState {
  const DriftAppState({
    required this.identity,
    required this.receiverBadge,
    required this.session,
    required this.animateSendingConnection,
  });

  final DriftAppIdentity identity;
  final ReceiverBadgeState receiverBadge;
  final ShellSessionState session;
  final bool animateSendingConnection;

  DriftAppState copyWith({
    DriftAppIdentity? identity,
    ReceiverBadgeState? receiverBadge,
    ShellSessionState? session,
    bool? animateSendingConnection,
  }) {
    return DriftAppState(
      identity: identity ?? this.identity,
      receiverBadge: receiverBadge ?? this.receiverBadge,
      session: session ?? this.session,
      animateSendingConnection:
          animateSendingConnection ?? this.animateSendingConnection,
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

  TransferStage get receiveStage => switch (session) {
    ReceiveOfferSession() => TransferStage.review,
    ReceiveTransferSession() => TransferStage.waiting,
    ReceiveResultSession() => TransferStage.completed,
    _ => TransferStage.idle,
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

  List<TransferItemViewData> get sendItems => switch (session) {
    SendDraftSession(:final items) => items,
    SendTransferSession(:final items) => items,
    SendResultSession(:final items) => items,
    _ => const [],
  };

  List<TransferItemViewData> get receiveItems => switch (session) {
    ReceiveOfferSession(:final items) => items,
    ReceiveTransferSession(:final items) => items,
    ReceiveResultSession(:final items) => items,
    _ => const [],
  };

  List<TransferDisplayItemViewData> get sendDisplayItems =>
      _displayItemsFor(sendItems, sendTransferPlan, sendTransferSnapshot);

  List<TransferDisplayItemViewData> get receiveDisplayItems => _displayItemsFor(
    receiveItems,
    receiveTransferPlan,
    receiveTransferSnapshot,
  );

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

  TransferSummaryViewData? get receiveSummary => switch (session) {
    ReceiveOfferSession(:final summary) => summary,
    ReceiveTransferSession(:final summary) => summary,
    ReceiveResultSession(:final summary) => summary,
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

  TransferResultSession? get transferResultSession => switch (session) {
    SendResultSession() => session as SendResultSession,
    ReceiveResultSession() => session as ReceiveResultSession,
    _ => null,
  };

  TransferResultViewData? get transferResult => switch (session) {
    SendResultSession(:final success, :final summary, :final metrics) =>
      TransferResultViewData(
        tone: success
            ? TransferResultToneData.success
            : TransferResultToneData.error,
        title: success
            ? 'Transfer complete'
            : _isCancelledMessage(summary.statusMessage)
            ? 'Transfer cancelled'
            : 'Transfer failed',
        message: summary.statusMessage,
        metrics: success ? metrics : null,
        primaryLabel: success ? 'Done' : null,
      ),
    ReceiveResultSession(:final success, :final summary, :final metrics) =>
      TransferResultViewData(
        tone: success
            ? TransferResultToneData.success
            : TransferResultToneData.error,
        title: success ? 'Files saved' : 'Transfer cancelled',
        message: summary.statusMessage,
        metrics: success ? metrics : null,
        primaryLabel: 'Done',
      ),
    _ => null,
  };

  bool get hasActiveTransfer => session is! IdleSession;

  bool get canGoBack => session is! IdleSession;

  bool get showShellBackButton => switch (session) {
    IdleSession() => false,
    SendResultSession(:final success) => !success,
    ReceiveResultSession() => false,
    ReceiveTransferSession() => false,
    _ => true,
  };

  bool get discoverableEnabled =>
      discoverableByDefault && (session is IdleSession);

  ShellView get shellView => shellViewFor(this);
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
        size: _formatBytes(_bigIntToInt(file.size)),
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
              : '${_formatBytes(transferred)} / ${_formatBytes(total)}',
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

String _formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unitIndex = 0;

  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }

  final decimals = value >= 10 || unitIndex == 0 ? 0 : 1;
  final formatted = value.toStringAsFixed(decimals);
  return '$formatted ${units[unitIndex]}';
}

bool _isCancelledMessage(String message) =>
    message.toLowerCase().contains('cancel');

sealed class ShellSessionState {
  const ShellSessionState();
}

sealed class TransferResultSession extends ShellSessionState {
  const TransferResultSession({
    required this.items,
    required this.summary,
    this.metrics,
    this.plan,
    this.snapshot,
  });

  final List<TransferItemViewData> items;
  final TransferSummaryViewData summary;
  final List<TransferMetricRow>? metrics;
  final rust_transfer.TransferPlanData? plan;
  final rust_transfer.TransferSnapshotData? snapshot;
}

class IdleSession extends ShellSessionState {
  const IdleSession();
}

class SendDraftSession extends ShellSessionState {
  const SendDraftSession({
    required this.items,
    required this.isInspecting,
    required this.nearbyDestinations,
    required this.nearbyScanInFlight,
    required this.nearbyScanCompletedOnce,
    required this.destinationCode,
    this.selectedDestination,
  });

  final List<TransferItemViewData> items;
  final bool isInspecting;
  final List<SendDestinationViewData> nearbyDestinations;
  final bool nearbyScanInFlight;
  final bool nearbyScanCompletedOnce;
  final String destinationCode;
  final SendDestinationViewData? selectedDestination;

  SendDraftSession copyWith({
    List<TransferItemViewData>? items,
    bool? isInspecting,
    List<SendDestinationViewData>? nearbyDestinations,
    bool? nearbyScanInFlight,
    bool? nearbyScanCompletedOnce,
    String? destinationCode,
    SendDestinationViewData? selectedDestination,
    bool clearSelectedDestination = false,
  }) {
    return SendDraftSession(
      items: items ?? this.items,
      isInspecting: isInspecting ?? this.isInspecting,
      nearbyDestinations: nearbyDestinations ?? this.nearbyDestinations,
      nearbyScanInFlight: nearbyScanInFlight ?? this.nearbyScanInFlight,
      nearbyScanCompletedOnce:
          nearbyScanCompletedOnce ?? this.nearbyScanCompletedOnce,
      destinationCode: destinationCode ?? this.destinationCode,
      selectedDestination: clearSelectedDestination
          ? null
          : (selectedDestination ?? this.selectedDestination),
    );
  }
}

enum SendTransferSessionPhase {
  connecting,
  waitingForDecision,
  accepted,
  declined,
  sending,
  cancelling,
}

class SendTransferSession extends ShellSessionState {
  const SendTransferSession({
    required this.phase,
    required this.items,
    required this.summary,
    this.plan,
    this.snapshot,
    this.remoteDeviceType,
    this.payloadBytesSent,
    this.payloadTotalBytes,
    this.payloadSpeedLabel,
    this.payloadEtaLabel,
  });

  final SendTransferSessionPhase phase;
  final List<TransferItemViewData> items;
  final TransferSummaryViewData summary;
  final rust_transfer.TransferPlanData? plan;
  final rust_transfer.TransferSnapshotData? snapshot;
  final String? remoteDeviceType;
  final int? payloadBytesSent;
  final int? payloadTotalBytes;
  final String? payloadSpeedLabel;
  final String? payloadEtaLabel;

  SendTransferSession copyWith({
    SendTransferSessionPhase? phase,
    List<TransferItemViewData>? items,
    TransferSummaryViewData? summary,
    rust_transfer.TransferPlanData? plan,
    rust_transfer.TransferSnapshotData? snapshot,
    String? remoteDeviceType,
    int? payloadBytesSent,
    int? payloadTotalBytes,
    String? payloadSpeedLabel,
    String? payloadEtaLabel,
  }) {
    return SendTransferSession(
      phase: phase ?? this.phase,
      items: items ?? this.items,
      summary: summary ?? this.summary,
      plan: plan ?? this.plan,
      snapshot: snapshot ?? this.snapshot,
      remoteDeviceType: remoteDeviceType ?? this.remoteDeviceType,
      payloadBytesSent: payloadBytesSent ?? this.payloadBytesSent,
      payloadTotalBytes: payloadTotalBytes ?? this.payloadTotalBytes,
      payloadSpeedLabel: payloadSpeedLabel ?? this.payloadSpeedLabel,
      payloadEtaLabel: payloadEtaLabel ?? this.payloadEtaLabel,
    );
  }
}

class SendResultSession extends TransferResultSession {
  const SendResultSession({
    required this.success,
    required super.items,
    required super.summary,
    super.metrics,
    super.plan,
    super.snapshot,
    this.remoteDeviceType,
  }) : super();

  final bool success;
  final String? remoteDeviceType;
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
  final int? payloadBytesReceived;
  final int? payloadTotalBytes;
  final String? senderDeviceType;
}

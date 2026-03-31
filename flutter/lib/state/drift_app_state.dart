import 'package:flutter/foundation.dart';

import '../core/models/transfer_models.dart';
import '../shell/shell_routing.dart';
import 'app_identity.dart';
import 'receiver_service_source.dart';

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
  String get idleReceiveCode => receiverBadge.code;
  String get idleReceiveStatus => receiverBadge.status;

  TransferDirection get mode => switch (session) {
    ReceiveIdleSession() ||
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
      SendTransferSessionPhase.sending => TransferStage.waiting,
    },
    SendResultSession(:final success) =>
      success ? TransferStage.completed : TransferStage.error,
    _ => TransferStage.idle,
  };

  TransferStage get receiveStage => switch (session) {
    ReceiveIdleSession() => TransferStage.idle,
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

  String get receiveCode => switch (session) {
    ReceiveIdleSession() => '',
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

  List<SendDestinationViewData> get nearbySendDestinations => switch (session) {
    SendDraftSession(:final nearbyDestinations) => nearbyDestinations,
    _ => const [],
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

  bool get hasReceivePayloadProgress =>
      receivePayloadBytesReceived != null &&
      receivePayloadTotalBytes != null &&
      receivePayloadTotalBytes! > 0;

  List<TransferMetricRow>? get receiveCompletionMetrics => switch (session) {
    ReceiveResultSession(:final metrics) => metrics,
    _ => null,
  };

  bool get hasActiveTransfer =>
      session is! IdleSession && session is! ReceiveIdleSession;

  bool get canGoBack => session is! IdleSession;

  bool get showShellBackButton => switch (session) {
    IdleSession() => false,
    SendResultSession(:final success) => !success,
    ReceiveResultSession() => false,
    ReceiveTransferSession() => false,
    _ => true,
  };

  bool get discoverableEnabled =>
      session is IdleSession || session is ReceiveIdleSession;

  ShellView get shellView => shellViewFor(this);
}

sealed class ShellSessionState {
  const ShellSessionState();
}

class IdleSession extends ShellSessionState {
  const IdleSession();
}

class ReceiveIdleSession extends ShellSessionState {
  const ReceiveIdleSession();
}

class SendDraftSession extends ShellSessionState {
  const SendDraftSession({
    required this.items,
    required this.isInspecting,
    required this.nearbyDestinations,
    required this.nearbyScanInFlight,
    required this.nearbyScanCompletedOnce,
    required this.destinationCode,
  });

  final List<TransferItemViewData> items;
  final bool isInspecting;
  final List<SendDestinationViewData> nearbyDestinations;
  final bool nearbyScanInFlight;
  final bool nearbyScanCompletedOnce;
  final String destinationCode;

  SendDraftSession copyWith({
    List<TransferItemViewData>? items,
    bool? isInspecting,
    List<SendDestinationViewData>? nearbyDestinations,
    bool? nearbyScanInFlight,
    bool? nearbyScanCompletedOnce,
    String? destinationCode,
  }) {
    return SendDraftSession(
      items: items ?? this.items,
      isInspecting: isInspecting ?? this.isInspecting,
      nearbyDestinations: nearbyDestinations ?? this.nearbyDestinations,
      nearbyScanInFlight: nearbyScanInFlight ?? this.nearbyScanInFlight,
      nearbyScanCompletedOnce:
          nearbyScanCompletedOnce ?? this.nearbyScanCompletedOnce,
      destinationCode: destinationCode ?? this.destinationCode,
    );
  }
}

enum SendTransferSessionPhase { connecting, waitingForDecision, sending }

class SendTransferSession extends ShellSessionState {
  const SendTransferSession({
    required this.phase,
    required this.items,
    required this.summary,
    this.remoteDeviceType,
    this.payloadBytesSent,
    this.payloadTotalBytes,
    this.payloadSpeedLabel,
    this.payloadEtaLabel,
  });

  final SendTransferSessionPhase phase;
  final List<TransferItemViewData> items;
  final TransferSummaryViewData summary;
  final String? remoteDeviceType;
  final int? payloadBytesSent;
  final int? payloadTotalBytes;
  final String? payloadSpeedLabel;
  final String? payloadEtaLabel;

  SendTransferSession copyWith({
    SendTransferSessionPhase? phase,
    List<TransferItemViewData>? items,
    TransferSummaryViewData? summary,
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
      remoteDeviceType: remoteDeviceType ?? this.remoteDeviceType,
      payloadBytesSent: payloadBytesSent ?? this.payloadBytesSent,
      payloadTotalBytes: payloadTotalBytes ?? this.payloadTotalBytes,
      payloadSpeedLabel: payloadSpeedLabel ?? this.payloadSpeedLabel,
      payloadEtaLabel: payloadEtaLabel ?? this.payloadEtaLabel,
    );
  }
}

class SendResultSession extends ShellSessionState {
  const SendResultSession({
    required this.success,
    required this.items,
    required this.summary,
    this.metrics,
    this.remoteDeviceType,
  });

  final bool success;
  final List<TransferItemViewData> items;
  final TransferSummaryViewData summary;
  final List<TransferMetricRow>? metrics;
  final String? remoteDeviceType;
}

class ReceiveOfferSession extends ShellSessionState {
  const ReceiveOfferSession({
    required this.items,
    required this.summary,
    required this.decisionPending,
    required this.payloadTotalBytes,
  });

  final List<TransferItemViewData> items;
  final TransferSummaryViewData summary;
  final bool decisionPending;
  final int? payloadTotalBytes;
}

class ReceiveTransferSession extends ShellSessionState {
  const ReceiveTransferSession({
    required this.items,
    required this.summary,
    this.payloadBytesReceived,
    this.payloadTotalBytes,
  });

  final List<TransferItemViewData> items;
  final TransferSummaryViewData summary;
  final int? payloadBytesReceived;
  final int? payloadTotalBytes;

  ReceiveTransferSession copyWith({
    List<TransferItemViewData>? items,
    TransferSummaryViewData? summary,
    int? payloadBytesReceived,
    int? payloadTotalBytes,
  }) {
    return ReceiveTransferSession(
      items: items ?? this.items,
      summary: summary ?? this.summary,
      payloadBytesReceived: payloadBytesReceived ?? this.payloadBytesReceived,
      payloadTotalBytes: payloadTotalBytes ?? this.payloadTotalBytes,
    );
  }
}

class ReceiveResultSession extends ShellSessionState {
  const ReceiveResultSession({
    required this.items,
    required this.summary,
    this.metrics,
    this.payloadBytesReceived,
    this.payloadTotalBytes,
  });

  final List<TransferItemViewData> items;
  final TransferSummaryViewData summary;
  final List<TransferMetricRow>? metrics;
  final int? payloadBytesReceived;
  final int? payloadTotalBytes;
}

import '../../core/models/transfer_models.dart';
import '../../state/shell_session_state.dart';
import '../../state/transfer_result_state.dart';
import '../../src/rust/api/transfer.dart' as rust_transfer;

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
    required this.outcome,
    required super.items,
    required super.summary,
    super.metrics,
    super.plan,
    super.snapshot,
    this.remoteDeviceType,
  }) : super();

  final bool success;
  final TransferResultOutcomeData outcome;
  final String? remoteDeviceType;
}

import '../../features/receive/receive_mapper.dart';
import '../../platform/send_transfer_source.dart';
import '../../state/drift_app_state.dart';
import '../../state/drift_sample_data.dart';
import 'send_mapper.dart' as send_mapper;

ShellSessionState reduceSendTransferUpdate({
  required DriftAppState state,
  required SendTransferUpdate update,
  required DateTime? payloadStartedAt,
}) {
  final items = state.sendItems.isEmpty ? sampleSendItems : state.sendItems;
  final existingSummary = state.sendSummary ?? sampleSendSummary;
  final summary = existingSummary.copyWith(
    itemCount: update.itemCount,
    totalSize: update.totalSize,
    code: state.sendDestinationCode,
    destinationLabel: update.destinationLabel,
    statusMessage: update.errorMessage ?? update.statusMessage,
  );
  final progress = progressFromSnapshot(update.snapshot);
  final bytesTransferred =
      progress.bytesTransferred ?? (update.bytesSent > 0 ? update.bytesSent : null);

  return switch (update.phase) {
    SendTransferUpdatePhase.connecting => SendTransferSession(
      phase: SendTransferSessionPhase.connecting,
      items: items,
      summary: summary,
      plan: update.plan ?? state.sendTransferPlan,
      snapshot: update.snapshot,
      remoteDeviceType: update.remoteDeviceType,
    ),
    SendTransferUpdatePhase.waitingForDecision => SendTransferSession(
      phase: SendTransferSessionPhase.waitingForDecision,
      items: items,
      summary: summary,
      plan: update.plan ?? state.sendTransferPlan,
      snapshot: update.snapshot,
      remoteDeviceType: update.remoteDeviceType,
    ),
    SendTransferUpdatePhase.accepted => SendTransferSession(
      phase: SendTransferSessionPhase.accepted,
      items: items,
      summary: summary,
      plan: update.plan ?? state.sendTransferPlan,
      snapshot: update.snapshot,
      remoteDeviceType: update.remoteDeviceType,
    ),
    SendTransferUpdatePhase.declined => SendResultSession(
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
    SendTransferUpdatePhase.sending => SendTransferSession(
      phase: SendTransferSessionPhase.sending,
      items: items,
      summary: summary,
      plan: update.plan ?? state.sendTransferPlan,
      snapshot: update.snapshot,
      remoteDeviceType: update.remoteDeviceType,
      payloadBytesSent: bytesTransferred,
      payloadTotalBytes:
          progress.totalBytes ?? (update.totalBytes > 0 ? update.totalBytes : null),
      payloadSpeedLabel: progress.speedLabel,
      payloadEtaLabel: progress.etaLabel,
    ),
    SendTransferUpdatePhase.completed => SendResultSession(
      success: true,
      outcome: TransferResultOutcomeData.success,
      items: items,
      summary: summary,
      metrics: send_mapper.buildSendCompletionMetrics(
        update,
        payloadStartedAt: payloadStartedAt,
      ),
      plan: update.plan ?? state.sendTransferPlan,
      snapshot: update.snapshot,
      remoteDeviceType: update.remoteDeviceType,
    ),
    SendTransferUpdatePhase.cancelled => SendResultSession(
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
    SendTransferUpdatePhase.failed => SendResultSession(
      success: false,
      outcome: TransferResultOutcomeData.failed,
      items: items,
      summary: summary,
      plan: update.plan ?? state.sendTransferPlan,
      snapshot: update.snapshot,
      remoteDeviceType: update.remoteDeviceType,
    ),
  };
}

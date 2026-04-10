import 'package:flutter/foundation.dart';

import '../core/models/transfer_models.dart';
import '../shared/formatting/transfer_message_format.dart';

enum TransferResultOutcomeData { success, cancelled, declined, failed }

enum TransferResultPrimaryActionData {
  done,
  tryAgain,
  chooseAnotherDevice,
  sendAgain,
}

@immutable
class TransferResultViewData {
  const TransferResultViewData({
    required this.outcome,
    required this.title,
    required this.message,
    this.metrics,
    this.primaryAction,
    this.secondaryLabel,
  });

  final TransferResultOutcomeData outcome;
  final String title;
  final String message;
  final List<TransferMetricRow>? metrics;
  final TransferResultPrimaryActionData? primaryAction;
  final String? secondaryLabel;

  String? get primaryLabel => switch (primaryAction) {
    TransferResultPrimaryActionData.done => 'Done',
    TransferResultPrimaryActionData.tryAgain => 'Try again',
    TransferResultPrimaryActionData.chooseAnotherDevice =>
      'Choose another device',
    TransferResultPrimaryActionData.sendAgain => 'Send again',
    null => null,
  };
}

TransferResultViewData buildSendTransferResultViewData({
  required TransferResultOutcomeData outcome,
  required TransferSummaryViewData summary,
  required List<TransferMetricRow>? metrics,
}) {
  return switch (outcome) {
    TransferResultOutcomeData.success => TransferResultViewData(
      outcome: outcome,
      title: 'Transfer complete',
      message: summary.statusMessage,
      metrics: metrics,
      primaryAction: TransferResultPrimaryActionData.done,
    ),
    TransferResultOutcomeData.cancelled => const TransferResultViewData(
      outcome: TransferResultOutcomeData.cancelled,
      title: 'Transfer cancelled',
      message: 'The transfer was stopped before all files were sent.',
      primaryAction: TransferResultPrimaryActionData.sendAgain,
    ),
    TransferResultOutcomeData.declined => const TransferResultViewData(
      outcome: TransferResultOutcomeData.declined,
      title: 'Transfer declined',
      message: 'The receiving device chose not to accept this transfer.',
      primaryAction: TransferResultPrimaryActionData.chooseAnotherDevice,
    ),
    TransferResultOutcomeData.failed => TransferResultViewData(
      outcome: outcome,
      title: 'Transfer failed',
      message: sendFailureMessage(summary.statusMessage),
      primaryAction: TransferResultPrimaryActionData.tryAgain,
    ),
  };
}

TransferResultViewData buildReceiveTransferResultViewData({
  required TransferResultOutcomeData outcome,
  required TransferSummaryViewData summary,
  required List<TransferMetricRow>? metrics,
}) {
  return switch (outcome) {
    TransferResultOutcomeData.success => TransferResultViewData(
      outcome: outcome,
      title: 'Files saved',
      message: summary.statusMessage,
      metrics: metrics,
      primaryAction: TransferResultPrimaryActionData.done,
    ),
    TransferResultOutcomeData.cancelled => const TransferResultViewData(
      outcome: TransferResultOutcomeData.cancelled,
      title: 'Receive cancelled',
      message: 'Drift stopped receiving before all files were saved.',
      primaryAction: TransferResultPrimaryActionData.done,
    ),
    TransferResultOutcomeData.declined => const TransferResultViewData(
      outcome: TransferResultOutcomeData.declined,
      title: 'Transfer declined',
      message: 'The transfer was declined before any files were received.',
      primaryAction: TransferResultPrimaryActionData.done,
    ),
    TransferResultOutcomeData.failed => TransferResultViewData(
      outcome: outcome,
      title: 'Couldn\'t finish receiving files',
      message: receiveFailureMessage(summary.statusMessage),
      primaryAction: TransferResultPrimaryActionData.done,
    ),
  };
}

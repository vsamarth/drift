import 'package:flutter/foundation.dart';

import 'state.dart';

enum TransferResultOutcome {
  success,
  cancelled,
  failed,
}

@immutable
class ResultMetric {
  const ResultMetric({required this.label, required this.value});

  final String label;
  final String value;
}

@immutable
class TransferResultViewData {
  const TransferResultViewData({
    required this.outcome,
    required this.title,
    required this.message,
    this.metrics,
    this.primaryLabel = 'Done',
  });

  final TransferResultOutcome outcome;
  final String title;
  final String message;
  final List<ResultMetric>? metrics;
  final String primaryLabel;
}

TransferResultViewData buildTransferResultViewData(TransferSessionState state) {
  final offer = state.incomingOffer;
  if (offer == null) {
    throw StateError('transfer result view data requires an incoming offer');
  }

  return switch (state.phase) {
    TransferSessionPhase.completed => TransferResultViewData(
      outcome: TransferResultOutcome.success,
      title: 'Files saved',
      message: 'Saved to ${offer.destinationLabel}',
      metrics: [
        ResultMetric(label: 'From', value: _displaySender(offer.sender.displayName)),
        ResultMetric(label: 'Saved to', value: offer.destinationLabel),
        ResultMetric(label: 'Files', value: '${state.result!.completedFiles}'),
        ResultMetric(label: 'Size', value: _formatBytes(state.result!.totalBytes)),
      ],
    ),
    TransferSessionPhase.cancelled => TransferResultViewData(
      outcome: TransferResultOutcome.cancelled,
      title: 'Receive cancelled',
      message:
          state.errorMessage ??
          'Drift stopped receiving before all files were saved.',
    ),
    TransferSessionPhase.failed => TransferResultViewData(
      outcome: TransferResultOutcome.failed,
      title: 'Couldn\'t finish receiving files',
      message: state.errorMessage ?? 'Couldn\'t finish receiving files.',
    ),
    _ => throw StateError('transfer result view data requires a terminal state'),
  };
}

String _displaySender(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? 'Unknown sender' : trimmed;
}

String _formatBytes(BigInt bytes) {
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

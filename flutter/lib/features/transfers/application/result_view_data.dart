import 'package:flutter/foundation.dart';

import 'format_utils.dart';
import 'identity.dart';
import 'manifest.dart';
import 'state.dart';

enum TransferResultOutcome { success, cancelled, failed }

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
    required this.deviceName,
    this.deviceType,
    this.manifestItems,
    this.durationLabel,
    this.averageSpeedLabel,
    this.totalSizeLabel,
    this.fileCountLabel,
  });

  final TransferResultOutcome outcome;
  final String title;
  final String message;
  final List<ResultMetric>? metrics;
  final String primaryLabel;
  final String deviceName;
  final DeviceType? deviceType;
  final List<TransferManifestItem>? manifestItems;

  // High-level summary stats
  final String? durationLabel;
  final String? averageSpeedLabel;
  final String? totalSizeLabel;
  final String? fileCountLabel;
}

TransferResultViewData buildTransferResultViewData(TransferSessionState state) {
  final offer = state.incomingOffer;
  if (offer == null) {
    throw StateError('transfer result view data requires an incoming offer');
  }

  final deviceName = _displaySender(offer.sender.deviceName);
  final deviceType = offer.sender.deviceType;
  final manifestItems = offer.manifest.items;

  return switch (state.phase) {
    TransferSessionPhase.completed => TransferResultViewData(
      outcome: TransferResultOutcome.success,
      title: 'Files saved',
      message: 'Saved to ${offer.destinationLabel}',
      deviceName: deviceName,
      deviceType: deviceType,
      manifestItems: manifestItems,
      durationLabel: _formatDuration(state.result?.duration),
      averageSpeedLabel: state.result?.averageSpeedLabel,
      totalSizeLabel: formatBytes(state.result?.totalBytes ?? BigInt.zero),
      fileCountLabel: '${state.result?.completedFiles ?? 0} files',
      metrics: [
        ResultMetric(label: 'From', value: deviceName),
        ResultMetric(label: 'Saved to', value: offer.destinationLabel),
        ResultMetric(label: 'Files', value: '${state.result!.completedFiles}'),
        ResultMetric(
          label: 'Size',
          value: formatBytes(state.result!.totalBytes),
        ),
      ],
    ),
    TransferSessionPhase.cancelled => TransferResultViewData(
      outcome: TransferResultOutcome.cancelled,
      title: 'Receive cancelled',
      message:
          state.errorMessage ??
          'Drift stopped receiving before all files were saved.',
      deviceName: deviceName,
      deviceType: deviceType,
      manifestItems: manifestItems,
    ),
    TransferSessionPhase.failed => TransferResultViewData(
      outcome: TransferResultOutcome.failed,
      title: 'Couldn\'t finish receiving files',
      message: state.errorMessage ?? 'Couldn\'t finish receiving files.',
      deviceName: deviceName,
      deviceType: deviceType,
      manifestItems: manifestItems,
    ),
    _ => throw StateError(
      'transfer result view data requires a terminal state',
    ),
  };
}

String _displaySender(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? 'Unknown sender' : trimmed;
}

String? _formatDuration(Duration? duration) {
  if (duration == null) return null;
  if (duration.inSeconds < 60) {
    return '${duration.inSeconds}s';
  }
  return '${duration.inMinutes}m ${duration.inSeconds % 60}s';
}

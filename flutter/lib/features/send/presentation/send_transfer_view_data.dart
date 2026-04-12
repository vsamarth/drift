import 'package:flutter/material.dart';

import '../../../theme/drift_theme.dart';
import '../../transfers/presentation/widgets/sending_connection_strip.dart';
import '../../transfers/presentation/widgets/transfer_presentation_helpers.dart';
import '../application/model.dart';
import '../application/state.dart';
import '../application/transfer_state.dart';

@immutable
class SendTransferPhaseVisualData {
  const SendTransferPhaseVisualData({
    required this.statusLabel,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.icon,
    required this.showSpinner,
  });

  final String statusLabel;
  final String title;
  final String subtitle;
  final Color accentColor;
  final IconData icon;
  final bool showSpinner;
}

enum SendTransferFileState { pending, active, completed }

@immutable
class SendTransferFileViewData {
  const SendTransferFileViewData({
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.sizeLabel,
    required this.state,
    this.progressFraction,
    this.statusLabel,
  });

  final String name;
  final String path;
  final BigInt sizeBytes;
  final String sizeLabel;
  final SendTransferFileState state;
  final double? progressFraction;
  final String? statusLabel;
}

@immutable
class SendTransferMetricData {
  const SendTransferMetricData({required this.label, required this.value});

  final String label;
  final String value;
}

@immutable
class SendTransferPageData {
  const SendTransferPageData({
    required this.visual,
    required this.metrics,
    required this.files,
    required this.progressFraction,
    required this.progressLabel,
    required this.speedLabel,
    required this.etaLabel,
    required this.localLabel,
    required this.localDeviceType,
    required this.remoteLabel,
    required this.remoteDeviceType,
    required this.stripMode,
    this.durationLabel,
    this.averageSpeedLabel,
  });

  final SendTransferPhaseVisualData visual;
  final List<SendTransferMetricData> metrics;
  final List<SendTransferFileViewData> files;
  final double? progressFraction;
  final String? progressLabel;
  final String? speedLabel;
  final String? etaLabel;
  final String localLabel;
  final String localDeviceType;
  final String remoteLabel;
  final String? remoteDeviceType;
  final SendingStripMode? stripMode;
  final String? durationLabel;
  final String? averageSpeedLabel;
}

SendTransferPageData buildSendTransferPageData({
  required SendState state,
  required SendRequestData request,
}) {
  return switch (state) {
    SendStateIdle() || SendStateDrafting() => SendTransferPageData(
      visual: const SendTransferPhaseVisualData(
        statusLabel: 'Waiting',
        title: 'Preparing transfer',
        subtitle: 'Gathering transfer details…',
        accentColor: kMuted,
        icon: Icons.hourglass_bottom_rounded,
        showSpinner: true,
      ),
      metrics: const [],
      files: const [],
      progressFraction: null,
      progressLabel: null,
      speedLabel: null,
      etaLabel: null,
      localLabel: request.deviceName,
      localDeviceType: request.deviceType,
      remoteLabel: request.lanDestinationLabel ?? request.code ?? 'Recipient',
      remoteDeviceType: null,
      stripMode: null,
      durationLabel: null,
      averageSpeedLabel: null,
    ),
    SendStateTransferring(:final transfer) ||
    SendStateResult(:final transfer) => SendTransferPageData(
      visual: _visualForState(state),
      metrics: _metricsForState(state),
      files: _filesForState(state),
      progressFraction: _progressFractionFor(transfer),
      progressLabel: _progressLabelFor(transfer),
      speedLabel: _speedLabelFor(transfer),
      etaLabel: _etaLabelFor(transfer),
      localLabel: request.deviceName,
      localDeviceType: request.deviceType,
      remoteLabel: transfer.destinationLabel,
      remoteDeviceType: transfer.remoteDeviceType,
      stripMode: _stripModeFor(transfer),
      durationLabel: state is SendStateResult ? _formatDuration(state.result.duration) : null,
      averageSpeedLabel: state is SendStateResult ? state.result.averageSpeedLabel : null,
    ),
  };
}

String? _formatDuration(Duration? duration) {
  if (duration == null) return null;
  if (duration.inSeconds < 60) {
    return '${duration.inSeconds}s';
  }
  return '${duration.inMinutes}m ${duration.inSeconds % 60}s';
}

SendTransferPhaseVisualData _visualForState(SendState state) {
  if (state is SendStateResult) {
    return switch (state.result.outcome) {
      SendTransferOutcome.success => const SendTransferPhaseVisualData(
        statusLabel: 'Success',
        title: 'Sent',
        subtitle: 'Files finished transferring successfully.',
        accentColor: Color(0xFF49B36C),
        icon: Icons.check_circle_rounded,
        showSpinner: false,
      ),
      SendTransferOutcome.cancelled => SendTransferPhaseVisualData(
        statusLabel: 'Cancelled',
        title: 'Transfer cancelled',
        subtitle: state.result.message,
        accentColor: const Color(0xFFC0912C),
        icon: Icons.do_not_disturb_on_rounded,
        showSpinner: false,
      ),
      SendTransferOutcome.declined => SendTransferPhaseVisualData(
        statusLabel: 'Declined',
        title: 'Transfer declined',
        subtitle: state.result.message,
        accentColor: const Color(0xFFB86A2B),
        icon: Icons.block_rounded,
        showSpinner: false,
      ),
      SendTransferOutcome.failed => SendTransferPhaseVisualData(
        statusLabel: 'Failed',
        title: state.result.title,
        subtitle: state.result.message,
        accentColor: const Color(0xFFCC3333),
        icon: Icons.error_rounded,
        showSpinner: false,
      ),
    };
  }

  if (state is SendStateTransferring) {
    final transfer = state.transfer;
    return switch (transfer.phase) {
      SendTransferPhase.connecting => SendTransferPhaseVisualData(
        statusLabel: 'Connecting',
        title: 'Connecting to recipient',
        subtitle: transfer.statusMessage,
        accentColor: kAccentCyanStrong,
        icon: Icons.sync_rounded,
        showSpinner: true,
      ),
      SendTransferPhase.waitingForDecision => SendTransferPhaseVisualData(
        statusLabel: 'Waiting',
        title: 'Waiting for the other device to confirm',
        subtitle: transfer.statusMessage,
        accentColor: kAccentCyanStrong,
        icon: Icons.hourglass_top_rounded,
        showSpinner: true,
      ),
      SendTransferPhase.accepted => SendTransferPhaseVisualData(
        statusLabel: 'Accepted',
        title: 'Receiver accepted',
        subtitle: transfer.statusMessage,
        accentColor: kAccentCyanStrong,
        icon: Icons.check_circle_outline_rounded,
        showSpinner: false,
      ),
      SendTransferPhase.sending => SendTransferPhaseVisualData(
        statusLabel: 'Sending',
        title: 'Sending files',
        subtitle: transfer.statusMessage,
        accentColor: kAccentCyanStrong,
        icon: Icons.upload_rounded,
        showSpinner: true,
      ),
      SendTransferPhase.cancelling => SendTransferPhaseVisualData(
        statusLabel: 'Cancelling',
        title: 'Stopping transfer',
        subtitle: transfer.statusMessage,
        accentColor: const Color(0xFFC0912C),
        icon: Icons.close_rounded,
        showSpinner: true,
      ),
      SendTransferPhase.completed => const SendTransferPhaseVisualData(
        statusLabel: 'Success',
        title: 'Sent',
        subtitle: 'Files finished transferring successfully.',
        accentColor: Color(0xFF49B36C),
        icon: Icons.check_circle_rounded,
        showSpinner: false,
      ),
      SendTransferPhase.declined => SendTransferPhaseVisualData(
        statusLabel: 'Declined',
        title: 'Transfer declined',
        subtitle: transfer.statusMessage,
        accentColor: const Color(0xFFB86A2B),
        icon: Icons.block_rounded,
        showSpinner: false,
      ),
      SendTransferPhase.cancelled => SendTransferPhaseVisualData(
        statusLabel: 'Cancelled',
        title: 'Transfer cancelled',
        subtitle: transfer.statusMessage,
        accentColor: const Color(0xFFC0912C),
        icon: Icons.do_not_disturb_on_rounded,
        showSpinner: false,
      ),
      SendTransferPhase.failed => SendTransferPhaseVisualData(
        statusLabel: 'Failed',
        title: 'Send failed',
        subtitle: transfer.error?.message ?? transfer.statusMessage,
        accentColor: const Color(0xFFCC3333),
        icon: Icons.error_rounded,
        showSpinner: false,
      ),
    };
  }

  throw StateError('Unexpected state for visual data: $state');
}

List<SendTransferMetricData> _metricsForState(SendState state) {
  final (transfer, request) = switch (state) {
    SendStateTransferring(:final transfer, :final request) => (
      transfer,
      request,
    ),
    SendStateResult(:final transfer, :final request) => (transfer, request),
    _ => throw StateError('Metrics requires an active or completed transfer'),
  };

  final metrics = <SendTransferMetricData>[
    SendTransferMetricData(
      label: 'Destination',
      value: transfer.destinationLabel,
    ),
    SendTransferMetricData(
      label: 'Files',
      value: _fileCountLabel(transfer.itemCount),
    ),
    SendTransferMetricData(
      label: 'Size',
      value: formatBytes(transfer.totalSize),
    ),
  ];

  final progressLabel = _progressLabelFor(transfer);
  if (progressLabel != null) {
    metrics.add(SendTransferMetricData(label: 'Sent', value: progressLabel));
  }

  if (transfer.remoteDeviceType != null &&
      transfer.remoteDeviceType!.trim().isNotEmpty) {
    metrics.add(
      SendTransferMetricData(
        label: 'Remote device',
        value: transfer.remoteDeviceType!,
      ),
    );
  }

  if (state is SendStateResult && request.serverUrl != null) {
    metrics.add(
      SendTransferMetricData(label: 'Server', value: request.serverUrl!),
    );
  }

  return metrics;
}

List<SendTransferFileViewData> _filesForState(SendState state) {
  final (transfer, items, request) = switch (state) {
    SendStateTransferring(:final transfer, :final items, :final request) => (
      transfer,
      items,
      request,
    ),
    SendStateResult(:final transfer, :final items, :final request) => (
      transfer,
      items,
      request,
    ),
    _ => throw StateError('Files requires an active or completed transfer'),
  };

  final plan = transfer.plan;
  final snapshot = transfer.snapshot;
  final roots = _buildDisplayRoots(
    requestPaths: request.paths,
    itemPaths: items.map((item) => item.path),
  );

  if (plan == null) {
    return items
        .map(
          (item) => SendTransferFileViewData(
            name: item.name,
            path: _relativeDisplayPath(item.path, roots),
            sizeBytes: item.sizeBytes,
            sizeLabel: formatBytes(item.sizeBytes),
            state: SendTransferFileState.pending,
          ),
        )
        .toList(growable: false);
  }

  return plan.files
      .map((file) {
        final relativePath = _relativeDisplayPath(file.path, roots);
        final fileName = _fileNameFromPath(relativePath);
        if (snapshot == null) {
          return SendTransferFileViewData(
            name: fileName,
            path: relativePath,
            sizeBytes: file.size,
            sizeLabel: formatBytes(file.size),
            state: SendTransferFileState.pending,
          );
        }

        final isCompleted = file.id < snapshot.completedFiles;
        if (isCompleted) {
          return SendTransferFileViewData(
            name: fileName,
            path: relativePath,
            sizeBytes: file.size,
            sizeLabel: formatBytes(file.size),
            state: SendTransferFileState.completed,
            statusLabel: 'Done',
          );
        }

        final isActive = snapshot.activeFileId == file.id;
        if (isActive) {
          final activeBytes = snapshot.activeFileBytes ?? BigInt.zero;
          final progress = file.size == BigInt.zero
              ? 1.0
              : (activeBytes.toDouble() / file.size.toDouble()).clamp(0.0, 1.0);
          return SendTransferFileViewData(
            name: fileName,
            path: relativePath,
            sizeBytes: file.size,
            sizeLabel: formatBytes(file.size),
            state: SendTransferFileState.active,
            progressFraction: progress,
            statusLabel: activeBytes == BigInt.zero
                ? 'Preparing'
                : '${formatBytes(activeBytes)} / ${formatBytes(file.size)}',
          );
        }

        return SendTransferFileViewData(
          name: fileName,
          path: relativePath,
          sizeBytes: file.size,
          sizeLabel: formatBytes(file.size),
          state: SendTransferFileState.pending,
        );
      })
      .toList(growable: false);
}

double? _progressFractionFor(SendTransferState transfer) {
  if (transfer.totalBytes == BigInt.zero) {
    return null;
  }
  return (transfer.bytesSent.toDouble() / transfer.totalBytes.toDouble()).clamp(
    0.0,
    1.0,
  );
}

String? _progressLabelFor(SendTransferState transfer) {
  if (transfer.totalBytes == BigInt.zero) {
    return null;
  }
  return '${formatBytes(transfer.bytesSent)} of ${formatBytes(transfer.totalBytes)}';
}

String? _speedLabelFor(SendTransferState transfer) {
  final speed = transfer.snapshot?.bytesPerSec;
  if (speed == null || speed <= BigInt.zero) {
    return null;
  }
  return '${formatBytes(speed)}/s';
}

String? _etaLabelFor(SendTransferState transfer) {
  final eta = transfer.snapshot?.etaSeconds;
  if (eta == null || eta <= BigInt.zero) {
    return null;
  }

  final seconds = eta.toInt();
  if (seconds < 60) {
    return '$seconds s left';
  }

  final minutes = seconds ~/ 60;
  final remainingSeconds = seconds % 60;
  if (minutes < 60) {
    return remainingSeconds == 0
        ? '$minutes m left'
        : '$minutes m $remainingSeconds s left';
  }

  final hours = minutes ~/ 60;
  final remainingMinutes = minutes % 60;
  return remainingMinutes == 0
      ? '$hours h left'
      : '$hours h $remainingMinutes m left';
}

SendingStripMode? _stripModeFor(SendTransferState transfer) {
  return switch (transfer.phase) {
    SendTransferPhase.connecting => SendingStripMode.looping,
    SendTransferPhase.waitingForDecision ||
    SendTransferPhase.accepted => SendingStripMode.waitingOnRecipient,
    SendTransferPhase.sending => SendingStripMode.transferring,
    _ => null,
  };
}

String _fileCountLabel(BigInt count) {
  if (count == BigInt.one) {
    return '1 file';
  }
  return '${count.toString()} files';
}

String _fileNameFromPath(String path) {
  final segments = path.split('/')..removeWhere((segment) => segment.isEmpty);
  return segments.isEmpty ? path : segments.last;
}

List<String> _buildDisplayRoots({
  required List<String> requestPaths,
  required Iterable<String> itemPaths,
}) {
  final roots = <String>{};
  for (final path in [...requestPaths, ...itemPaths]) {
    final normalized = _normalizePath(path);
    if (_isAbsolutePath(normalized)) {
      roots.add(normalized);
    }
  }
  return roots.toList(growable: false);
}

String _relativeDisplayPath(String path, List<String> roots) {
  final normalized = _normalizePath(path);
  if (!_isAbsolutePath(normalized)) {
    return normalized;
  }

  String? bestMatch;
  for (final root in roots) {
    if (normalized == root) {
      continue;
    }
    if (normalized.startsWith('$root/')) {
      final candidate = normalized.substring(root.length + 1);
      if (candidate.isEmpty) {
        continue;
      }
      if (bestMatch == null || candidate.length < bestMatch.length) {
        bestMatch = candidate;
      }
    }
  }

  return bestMatch ?? _fileNameFromPath(normalized);
}

bool _isAbsolutePath(String path) {
  return path.startsWith('/') || RegExp(r'^[A-Za-z]:/').hasMatch(path);
}

String _normalizePath(String path) {
  var normalized = path.trim().replaceAll('\\', '/');
  while (normalized.endsWith('/') && normalized.length > 1) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

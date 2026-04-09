import '../../core/models/transfer_models.dart';
import '../../shared/formatting/byte_format.dart';
import '../../src/rust/api/receiver.dart' as rust_receiver;
import '../../src/rust/api/transfer.dart' as rust_transfer;

class ReceiveProgressMetrics {
  const ReceiveProgressMetrics({
    this.bytesTransferred,
    this.totalBytes,
    this.speedLabel,
    this.etaLabel,
  });

  final int? bytesTransferred;
  final int? totalBytes;
  final String? speedLabel;
  final String? etaLabel;
}

TransferItemViewData incomingFileToViewData(
  rust_receiver.ReceiverTransferFile file,
) {
  final path = file.path;
  final segments = path.split('/')..removeWhere((segment) => segment.isEmpty);
  final name = segments.isEmpty ? path : segments.last;
  final bytes = _bigIntToInt(file.size);
  return TransferItemViewData(
    name: name,
    path: path,
    size: formatBytes(bytes),
    kind: TransferItemKind.file,
    sizeBytes: bytes,
  );
}

List<TransferMetricRow>? buildReceiveCompletionMetrics({
  required TransferSummaryViewData summary,
  required int bytesReceived,
  required DateTime? startedAt,
}) {
  final rows = <TransferMetricRow>[];
  if (summary.senderName.isNotEmpty) {
    rows.add(TransferMetricRow(label: 'From', value: summary.senderName));
  }
  rows.add(
    TransferMetricRow(label: 'Saved to', value: summary.destinationLabel),
  );
  rows.add(TransferMetricRow(label: 'Files', value: '${summary.itemCount}'));
  rows.add(TransferMetricRow(label: 'Size', value: summary.totalSize));
  rows.addAll(
    _buildPerformanceMetrics(
      startedAt: startedAt,
      bytesTransferred: bytesReceived,
    ),
  );
  return rows;
}

ReceiveProgressMetrics progressFromSnapshot(
  rust_transfer.TransferSnapshotData? snapshot,
) {
  if (snapshot == null) {
    return const ReceiveProgressMetrics();
  }

  final bytesTransferred = _bigIntToInt(snapshot.bytesTransferred);
  final totalBytes = _bigIntToInt(snapshot.totalBytes);
  final bytesPerSec = snapshot.bytesPerSec == null
      ? null
      : _bigIntToInt(snapshot.bytesPerSec!);
  final etaSeconds = snapshot.etaSeconds == null
      ? null
      : _bigIntToInt(snapshot.etaSeconds!);

  return ReceiveProgressMetrics(
    bytesTransferred: bytesTransferred,
    totalBytes: totalBytes,
    speedLabel: bytesPerSec != null && bytesPerSec >= 16
        ? _formatBytesPerSecond(bytesPerSec.toDouble())
        : null,
    etaLabel: etaSeconds != null && etaSeconds > 0
        ? _formatEtaSeconds(etaSeconds.toDouble())
        : null,
  );
}

List<TransferMetricRow> _buildPerformanceMetrics({
  required DateTime? startedAt,
  required int bytesTransferred,
}) {
  final rows = <TransferMetricRow>[];
  if (startedAt == null) {
    return rows;
  }

  final now = DateTime.now();
  final transferElapsed = now.difference(startedAt);
  if (transferElapsed.inMilliseconds >= 200) {
    rows.add(
      TransferMetricRow(
        label: 'Transfer time',
        value: _formatElapsedDuration(transferElapsed),
      ),
    );
  }

  final payloadSec = transferElapsed.inMilliseconds / 1000.0;
  if (payloadSec >= 0.25 && bytesTransferred > 0) {
    rows.add(
      TransferMetricRow(
        label: 'Average speed',
        value: _formatBytesPerSecond(bytesTransferred / payloadSec),
      ),
    );
  }

  return rows;
}

int _bigIntToInt(BigInt value) {
  if (value.bitLength > 63) {
    return 0x7fffffffffffffff;
  }
  return value.toInt();
}

String _formatBytesPerSecond(double bps) {
  if (bps <= 0) {
    return '0 B/s';
  }
  final units = ['B/s', 'KB/s', 'MB/s', 'GB/s', 'TB/s'];
  var value = bps;
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  final decimals = value >= 10 || unitIndex == 0 ? 0 : 1;
  return '${value.toStringAsFixed(decimals)} ${units[unitIndex]}';
}

String _formatEtaSeconds(double seconds) {
  final duration = Duration(seconds: seconds.round());
  final minutes = duration.inMinutes;
  final secs = duration.inSeconds % 60;
  if (minutes <= 0) {
    return '$secs s';
  }
  if (secs == 0) {
    return '$minutes min';
  }
  return '$minutes min $secs s';
}

String _formatElapsedDuration(Duration duration) {
  final ms = duration.inMilliseconds;
  if (ms < 60 * 1000) {
    final sec = (ms / 1000).clamp(0.05, double.infinity);
    if (sec < 10) {
      return '${sec.toStringAsFixed(1)} s';
    }
    return '${sec.round()} s';
  }
  if (ms < 3600 * 1000) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return seconds == 0 ? '$minutes min' : '$minutes min $seconds s';
  }
  final hours = duration.inHours;
  final minutes = duration.inMinutes % 60;
  return minutes == 0 ? '$hours h' : '$hours h $minutes min';
}

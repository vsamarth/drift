import '../../core/models/transfer_models.dart';
import '../../platform/send_transfer_source.dart';

String formatCodeAsDestination(String code) {
  final prefix = code.substring(0, 3);
  final suffix = code.substring(3);
  return 'Code $prefix $suffix';
}

List<TransferMetricRow>? buildSendCompletionMetrics(
  SendTransferUpdate update, {
  required DateTime? payloadStartedAt,
}) {
  final rows = <TransferMetricRow>[];
  final recipient = update.destinationLabel.trim().isEmpty
      ? 'Recipient device'
      : update.destinationLabel;
  rows.add(TransferMetricRow(label: 'Sent to', value: recipient));
  rows.add(TransferMetricRow(label: 'Files', value: '${update.itemCount}'));
  rows.add(TransferMetricRow(label: 'Size', value: update.totalSize));
  rows.addAll(
    _buildPerformanceMetrics(
      startedAt: payloadStartedAt,
      bytesTransferred: update.bytesSent,
    ),
  );
  return rows;
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

String _formatBytesPerSecond(double bps) {
  const units = ['B/s', 'KB/s', 'MB/s', 'GB/s'];
  var value = bps;
  var index = 0;
  while (value >= 1024 && index < units.length - 1) {
    value /= 1024;
    index += 1;
  }
  final decimals = value >= 10 || index == 0 ? 0 : 1;
  return '${value.toStringAsFixed(decimals)} ${units[index]}';
}

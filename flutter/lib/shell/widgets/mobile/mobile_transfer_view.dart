import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/transfer_models.dart';
import '../../../core/theme/drift_theme.dart';
import '../../../state/drift_providers.dart';
import '../preview_list.dart';

class MobileTransferView extends ConsumerWidget {
  const MobileTransferView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(driftAppNotifierProvider);
    final notifier = ref.read(driftAppNotifierProvider.notifier);

    final isSending = state.mode == TransferDirection.send;
    final items = isSending ? state.sendItems : state.receiveItems;
    final summary = isSending ? state.sendSummary : state.receiveSummary;

    final progress = isSending
        ? (state.sendPayloadTotalBytes != null &&
                  state.sendPayloadTotalBytes! > 0
              ? (state.sendPayloadBytesSent ?? 0) / state.sendPayloadTotalBytes!
              : 0.0)
        : (state.receivePayloadTotalBytes != null &&
                  state.receivePayloadTotalBytes! > 0
              ? (state.receivePayloadBytesReceived ?? 0) /
                    state.receivePayloadTotalBytes!
              : 0.0);

    final status =
        summary?.statusMessage ?? (isSending ? 'Preparing...' : 'Waiting...');
    final title = isSending ? 'Sending' : 'Receiving';
    final destination = isSending
        ? (summary?.destinationLabel ?? 'Recipient')
        : (summary?.senderName ?? 'Sender');
    final transferredBytes = isSending
        ? (state.sendPayloadBytesSent ?? 0)
        : (state.receivePayloadBytesReceived ?? 0);
    final totalBytes = isSending
        ? (state.sendPayloadTotalBytes ?? 0)
        : (state.receivePayloadTotalBytes ?? 0);
    final itemCount = summary?.itemCount ?? items.length;
    final totalSizeLabel = summary?.totalSize ?? _formatBytes(totalBytes);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 160,
                  height: 160,
                  child: CircularProgressIndicator(
                    value: progress > 0 ? progress : null,
                    strokeWidth: 8,
                    strokeCap: StrokeCap.round,
                    backgroundColor: kMuted.withValues(alpha: 0.1),
                    color: kAccentCyanStrong,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${(progress * 100).toInt()}%',
                      style: driftSans(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: kInk,
                      ),
                    ),
                    if (isSending && state.sendTransferSpeedLabel != null)
                      Text(
                        state.sendTransferSpeedLabel!,
                        style: driftSans(fontSize: 12, color: kMuted),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          Text(
            title,
            style: driftSans(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: kMuted,
              letterSpacing: 1.2,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            destination,
            style: driftSans(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: kInk,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            status,
            style: driftSans(fontSize: 14, color: kMuted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: kSurface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: kBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isSending ? 'Transfer details' : 'Receive details',
                  style: driftSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: kInk,
                  ),
                ),
                const SizedBox(height: 12),
                _MetricRow(
                  label: 'Payload',
                  value:
                      '${_formatBytes(transferredBytes)} / ${_formatBytes(totalBytes)}',
                ),
                _MetricRow(label: 'Items', value: '$itemCount'),
                _MetricRow(label: 'Selection', value: totalSizeLabel),
                if (isSending && state.sendTransferSpeedLabel != null)
                  _MetricRow(
                    label: 'Speed',
                    value: state.sendTransferSpeedLabel!,
                  ),
                if (isSending && state.sendTransferEtaLabel != null)
                  _MetricRow(label: 'ETA', value: state.sendTransferEtaLabel!),
                if (items.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Files',
                    style: driftSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: kMuted,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final item in items.take(4))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '${item.name} · ${item.size}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: driftSans(fontSize: 13, color: kInk),
                      ),
                    ),
                  if (items.length > 4)
                    Text(
                      '+${items.length - 4} more',
                      style: driftSans(fontSize: 12, color: kMuted),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          PreviewList(items: items),
          const SizedBox(height: 16),
          if (isSending || state.receiveStage == TransferStage.waiting)
            FilledButton.tonal(
              onPressed: isSending
                  ? notifier.cancelSendInProgress
                  : notifier.declineReceiveOffer,
              style: FilledButton.styleFrom(
                foregroundColor: const Color(0xFFCC3333),
                backgroundColor: const Color(0xFFCC3333).withValues(alpha: 0.1),
              ),
              child: const Text('Cancel Transfer'),
            ),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: driftSans(fontSize: 13, color: kMuted)),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: driftSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: kInk,
              ),
            ),
          ),
        ],
      ),
    );
  }
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

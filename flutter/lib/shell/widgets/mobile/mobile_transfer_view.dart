import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/transfer_models.dart';
import '../../../core/theme/drift_theme.dart';
import '../../../state/drift_providers.dart';
import '../live_transfer_stats.dart';
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
          const SizedBox(height: 16),
          LiveTransferStats(
            speedLabel: isSending
                ? state.sendTransferSpeedLabel
                : state.receiveTransferSpeedLabel,
            etaLabel: isSending
                ? state.sendTransferEtaLabel
                : state.receiveTransferEtaLabel,
            center: true,
          ),
          const SizedBox(height: 24),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 16),
          PreviewList(items: items),
          const SizedBox(height: 16),
          if (isSending || state.receiveStage == TransferStage.waiting)
            FilledButton.tonal(
              onPressed: isSending
                  ? notifier.cancelSendInProgress
                  : notifier.cancelReceiveInProgress,
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

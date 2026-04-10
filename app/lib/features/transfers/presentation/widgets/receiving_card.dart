import 'package:flutter/material.dart';

import '../../application/state.dart';
import 'preview_table.dart';
import 'sending_connection_strip.dart';
import 'transfer_flow_layout.dart';
import 'transfer_live_stats.dart';
import 'transfer_presentation_helpers.dart';

class ReceivingCard extends StatelessWidget {
  const ReceivingCard({
    super.key,
    required this.offer,
    required this.progress,
    required this.animate,
    required this.onCancel,
  });

  final TransferIncomingOffer offer;
  final TransferTransferProgress progress;
  final bool animate;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final senderName = displaySender(offer.sender.displayName);
    final itemCount = offer.manifest.itemCount;
    final totalSize = formatBytes(offer.manifest.totalSizeBytes);
    final itemSummary = '${fileCountLabel(itemCount)} · $totalSize';
    final subtitle = offer.statusMessage.trim().isEmpty
        ? 'Receiving files...'
        : offer.statusMessage.trim();

    return SizedBox.expand(
      child: TransferFlowLayout(
        statusLabel: 'Receiving',
        statusColor: const Color(0xFFD4A824),
        title: senderName,
        subtitle: subtitle,
        explainer: TransferLiveStats(progress: progress),
        illustration: SendingConnectionStrip(
          localLabel: senderName,
          localDeviceType: deviceTypeLabel(offer.sender.deviceType),
          remoteLabel: 'Drift',
          remoteDeviceType: 'laptop',
          animate: animate,
          mode: SendingStripMode.transferring,
          transferProgress: progress.progressFraction,
        ),
        manifest: PreviewTable(
          items: offer.manifest.items,
          footerSummary: itemSummary,
        ),
        footer: Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: onCancel,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFCC3333),
                  backgroundColor: const Color(
                    0xFFCC3333,
                  ).withValues(alpha: 0.08),
                  minimumSize: const Size(0, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: const Color(0xFFCC3333).withValues(alpha: 0.15),
                    ),
                  ),
                ),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

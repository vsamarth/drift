import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/state.dart';
import 'package:app/features/send/presentation/widgets/content_summary_card.dart';
import 'package:app/features/send/presentation/widgets/recipient_avatar.dart';
import 'sending_connection_strip.dart';
import 'transfer_flow_layout.dart';
import 'transfer_live_stats.dart';
import 'transfer_presentation_helpers.dart';

class ReceivingCard extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final senderName = displaySender(offer.sender.displayName);
    final subtitle = offer.statusMessage.trim().isEmpty
        ? 'Receiving files...'
        : offer.statusMessage.trim();

    return SizedBox.expand(
      child: TransferFlowLayout(
        statusLabel: 'Receiving',
        statusColor: const Color(0xFFD4A824),
        subtitle: subtitle,
        explainer: TransferLiveStats(progress: progress),
        illustration: RecipientAvatar(
          deviceName: senderName,
          deviceType: deviceTypeLabel(offer.sender.deviceType),
          animate: animate,
          mode: SendingStripMode.transferring,
          progress: progress.progressFraction,
        ),
        manifest: ContentSummaryCard(
          items: offer.manifest.items,
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

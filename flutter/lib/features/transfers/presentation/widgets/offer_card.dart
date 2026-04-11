import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/state.dart';
import '../../../../theme/drift_theme.dart';
import 'package:app/features/send/presentation/widgets/content_summary_card.dart';
import 'package:app/features/send/presentation/widgets/recipient_avatar.dart';
import 'sending_connection_strip.dart';
import 'transfer_flow_layout.dart';
import 'transfer_presentation_helpers.dart';

class OfferCard extends ConsumerWidget {
  const OfferCard({
    super.key,
    required this.offer,
    required this.animate,
    required this.onAccept,
    required this.onDecline,
  });

  final TransferIncomingOffer offer;
  final bool animate;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final senderName = displaySender(offer.sender.displayName);
    final itemCount = offer.manifest.itemCount;
    final totalSize = formatBytes(offer.manifest.totalSizeBytes);

    return SizedBox.expand(
      child: TransferFlowLayout(
        statusLabel: 'Incoming',
        statusColor: const Color(0xFF4B98AA),
        subtitle: incomingSubtitle(itemCount, totalSize),
        explainer: Text(
          'Review the files and accept only if you trust the sender.',
          textAlign: TextAlign.center,
          style: driftSans(fontSize: 12, color: kSubtle, height: 1.4),
        ),
        illustration: RecipientAvatar(
          deviceName: senderName,
          deviceType: deviceTypeLabel(offer.sender.deviceType),
          animate: animate,
          mode: SendingStripMode.waitingOnRecipient,
        ),
        manifest: ContentSummaryCard(
          items: offer.manifest.items,
        ),
        footer: Row(
          children: [
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: onAccept,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4A8E9E),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text('Save to ${offer.saveRootLabel}'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 1,
              child: TextButton(
                onPressed: onDecline,
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
                child: const Text('Decline'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

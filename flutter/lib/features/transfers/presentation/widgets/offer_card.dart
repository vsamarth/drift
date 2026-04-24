import 'package:flutter/material.dart';

import '../../application/state.dart';
import '../../../../theme/drift_theme.dart';
import 'package:app/features/send/presentation/widgets/recipient_avatar.dart';
import 'manifest_tree_card.dart';
import 'sending_connection_strip.dart';
import 'transfer_flow_layout.dart';
import 'transfer_presentation_helpers.dart';

class OfferCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final senderName = displaySender(offer.sender.displayName);
    final itemCount = offer.manifest.itemCount;
    final totalSize = formatBytes(offer.manifest.totalSizeBytes);
    final willResume = offer.willResume;
    final subtitle = incomingSubtitle(itemCount, totalSize);

    return SizedBox.expand(
      child: TransferFlowLayout(
        statusLabel: 'Incoming',
        statusColor: const Color(0xFF4B98AA),
        subtitle: buildSubtitleText(subtitle),
        explainer: Text(
          willResume
              ? 'Resuming previous transfer. Drift will skip files you already have and download the rest. Accept only if you trust the sender.'
              : 'Review the files and accept only if you trust the sender.',
          textAlign: TextAlign.center,
          style: driftSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: kInk.withValues(alpha: 0.7),
            height: 1.4,
          ),
        ),
        illustration: RecipientAvatar(
          deviceName: senderName,
          deviceType: deviceTypeLabel(offer.sender.deviceType),
          animate: animate,
          mode: SendingStripMode.waitingOnRecipient,
        ),
        manifest: ManifestTreeCard(items: offer.manifest.items),
        footer: Row(
          children: [
            Expanded(
              flex: 3,
              child: FilledButton(
                onPressed: onAccept,
                style: FilledButton.styleFrom(
                  backgroundColor: kAccentCyanStrong,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'Save to ${offer.saveRootLabel}',
                  style: driftSans(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 1,
              child: TextButton(
                onPressed: onDecline,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFB34A4A),
                  minimumSize: const Size(0, 52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Decline',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/state.dart';
import 'package:app/features/send/presentation/widgets/recipient_avatar.dart';
import 'manifest_tree_card.dart';
import 'sending_connection_strip.dart';
import 'transfer_flow_layout.dart';
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
    String subtitle = offer.statusMessage.trim().isEmpty
        ? 'Receiving files...'
        : offer.statusMessage.trim();

    final extras = <String>[
      if (progress.speedLabel != null) progress.speedLabel!,
      if (progress.etaLabel != null) progress.etaLabel!,
    ];
    if (extras.isNotEmpty) {
      subtitle = extras.join(' | ');
    }

    return SizedBox.expand(
      child: TransferFlowLayout(
        statusLabel: 'Receiving',
        statusColor: const Color(0xFFD4A824),
        subtitle: subtitle,
        explainer: null,
        illustration: RecipientAvatar(
          deviceName: senderName,
          deviceType: deviceTypeLabel(offer.sender.deviceType),
          animate: animate,
          mode: SendingStripMode.transferring,
          progress: progress.progressFraction,
        ),
        manifest: ManifestTreeCard(
          items: offer.manifest.items,
        ),
        footer: Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: onCancel,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFB34A4A),
                  minimumSize: const Size(0, 52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Cancel',
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

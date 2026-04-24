import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/state.dart';
import 'package:app/features/send/presentation/widgets/recipient_avatar.dart';
import 'active_transfer_file_list.dart';
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

    final Widget subtitle;
    if (progress.speedLabel != null) {
      subtitle = buildSpeedLine(
        speedLabel: progress.speedLabel!,
        etaLabel: progress.etaLabel,
      );
    } else {
      subtitle = buildSubtitleText(
        offer.statusMessage.trim().isEmpty
            ? 'Receiving files...'
            : offer.statusMessage.trim(),
      );
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
        manifest: ActiveTransferFileList(
          items: offer.manifest.items,
          progress: progress,
        ),
        footer: progress.progressFraction >= 1.0
            ? const SizedBox(height: 52)
            : Row(
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

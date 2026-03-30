import 'package:flutter/material.dart';

import '../../core/models/transfer_models.dart';
import '../../core/theme/drift_theme.dart';
import '../../state/drift_controller.dart';
import 'preview_list.dart';
import 'sending_connection_strip.dart';

class ReceiveReviewCard extends StatelessWidget {
  const ReceiveReviewCard({super.key, required this.controller});

  final DriftController controller;

  @override
  Widget build(BuildContext context) {
    final summary = controller.receiveSummary;
    final senderName = _displaySender(summary?.senderName);
    final itemCount = summary?.itemCount ?? controller.receiveItems.length;
    final totalSize = summary?.totalSize ?? '';
    final itemSummary = '$itemCount${totalSize.isEmpty ? '' : ' · $totalSize'}';
    final saveRoot = summary?.destinationLabel.trim() ?? 'Downloads';

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Status pill ────────────────────────────────────────────────
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: Color(0xFF4B98AA),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Incoming',
                style: driftSans(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: kMuted,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // ── Sender name ────────────────────────────────────────────────
          Text(
            senderName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: driftSans(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: kInk,
              letterSpacing: -0.8,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _subtitle(itemCount, totalSize, saveRoot),
            style: driftSans(fontSize: 13, color: kMuted, height: 1.5),
          ),
          const SizedBox(height: 18),
          // ── Middle: connection strip + file table ──────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 2,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: SendingConnectionStrip(
                        // Sender on left, local receiver on right — data flows →
                        localLabel: senderName,
                        localDeviceType: 'laptop',
                        remoteLabel: controller.deviceName,
                        remoteDeviceType: controller.deviceType,
                        animate: true,
                        mode: SendingStripMode.waitingOnRecipient,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: PreviewTable(
                      items: controller.receiveItems,
                      footerSummary: itemSummary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ── Actions row ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: controller.acceptReceiveOffer,
                    child: Text('Save to $saveRoot'),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: controller.declineReceiveOffer,
                  child: const Text('Decline'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _displaySender(String? rawValue) {
  final trimmed = rawValue?.trim() ?? '';
  if (trimmed.isEmpty) return 'Unknown sender';
  return trimmed;
}

String _subtitle(int itemCount, String totalSize, String saveRoot) {
  final fileWord = itemCount == 1 ? 'file' : 'files';
  final sizePart = totalSize.isEmpty ? '' : ' ($totalSize)';
  return 'Wants to send you $itemCount $fileWord$sizePart.';
}

import 'package:flutter/material.dart';

import '../../core/models/transfer_models.dart';
import '../../core/theme/drift_theme.dart';
import '../../state/drift_controller.dart';
import 'preview_list.dart';

class SendCodeCard extends StatelessWidget {
  const SendCodeCard({
    super.key,
    required this.controller,
    required this.title,
    required this.status,
    this.primaryLabel,
    this.onPrimary,
  });

  final DriftController controller;
  final String title;
  final String status;
  final String? primaryLabel;
  final VoidCallback? onPrimary;

  @override
  Widget build(BuildContext context) {
    final summary = controller.sendSummary;
    final itemCount = summary?.itemCount ?? controller.sendItems.length;
    final totalSize = summary?.totalSize ?? '';
    final destinationLabel = _displayRecipient(summary?.destinationLabel);
    final stage = controller.sendStage;
    final dotColor = _dotColorFor(stage);
    final itemSummary =
        '$itemCount ${itemCount == 1 ? 'item' : 'items'}${totalSize.isEmpty ? '' : ' · $totalSize'}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: driftSans(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: kInk,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            status,
            style: driftSans(
              fontSize: 13,
              color: kMuted,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      destinationLabel,
                      style: driftSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: kInk,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      itemSummary,
                      style: driftSans(fontSize: 12, color: kMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),
          PreviewList(
            items: controller.visibleSendItems,
            hiddenItemCount: controller.hiddenSendItemCount,
          ),
          if (primaryLabel != null && onPrimary != null) ...[
            const SizedBox(height: 20),
            FilledButton(onPressed: onPrimary, child: Text(primaryLabel!)),
          ],
        ],
      ),
    );
  }
}

Color _dotColorFor(TransferStage stage) {
  return switch (stage) {
    TransferStage.ready => const Color(0xFF4B98AA),
    TransferStage.waiting => const Color(0xFFD4A824),
    TransferStage.completed => const Color(0xFF49B36C),
    TransferStage.error => const Color(0xFFCC3333),
    _ => const Color(0xFF4B98AA),
  };
}

String _displayRecipient(String? rawValue) {
  final trimmed = rawValue?.trim() ?? '';
  if (trimmed.isEmpty) {
    return 'Recipient device';
  }

  final normalized = trimmed
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final lowercase = normalized.toLowerCase();
  if (lowercase.isEmpty ||
      lowercase == 'unknown device' ||
      lowercase == 'unknown-device' ||
      lowercase == 'unknown') {
    return 'Recipient device';
  }

  return normalized;
}

import 'package:flutter/material.dart';

import '../../core/theme/drift_theme.dart';
import '../../state/drift_controller.dart';
import 'preview_list.dart';
import 'shell_surface_card.dart';

class SendCodeCard extends StatelessWidget {
  const SendCodeCard({
    super.key,
    required this.controller,
    required this.title,
    required this.status,
    required this.primaryLabel,
    required this.onPrimary,
  });

  final DriftController controller;
  final String title;
  final String status;
  final String primaryLabel;
  final VoidCallback onPrimary;

  @override
  Widget build(BuildContext context) {
    final summary = controller.sendSummary;

    return ShellSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: driftSans(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: kInk,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            status,
            style: driftSans(fontSize: 14, color: kMuted, height: 1.45),
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: kSurface2,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: kBorder),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: kSurface,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: kBorder),
                  ),
                  child: const Icon(
                    Icons.sync_outlined,
                    size: 17,
                    color: kMuted,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        summary?.destinationLabel ?? '',
                        style: driftSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: kInk,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${summary?.itemCount ?? 0} items · ${summary?.totalSize ?? ''}',
                        style: driftSans(fontSize: 12.5, color: kMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Files',
            style: driftSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: kMuted,
            ),
          ),
          const SizedBox(height: 10),
          PreviewList(
            items: controller.visibleSendItems,
            hiddenItemCount: controller.hiddenSendItemCount,
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: onPrimary, child: Text(primaryLabel)),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'package:app/theme/drift_theme.dart';
import 'package:app/features/send/presentation/widgets/recipient_avatar.dart';
import 'package:app/features/transfers/application/result_view_data.dart';
import 'package:app/features/transfers/presentation/widgets/manifest_tree_card.dart';
import 'sending_connection_strip.dart';
import 'transfer_flow_layout.dart';
import 'transfer_presentation_helpers.dart';

class TransferResultCard extends StatelessWidget {
  const TransferResultCard({
    super.key,
    required this.viewData,
    this.onPrimary,
    this.onSecondary,
    this.secondaryLabel,
  });

  final TransferResultViewData viewData;
  final VoidCallback? onPrimary;
  final VoidCallback? onSecondary;
  final String? secondaryLabel;

  @override
  Widget build(BuildContext context) {
    final visual = _visualForOutcome(viewData.outcome);

    return SizedBox.expand(
      child: TransferFlowLayout(
        statusLabel: visual.statusLabel,
        statusColor: visual.accentColor,
        subtitle: buildSubtitleText(viewData.message),
        explainer: _StatsGrid(viewData: viewData),
        illustration: RecipientAvatar(
          deviceName: viewData.deviceName,
          deviceType: viewData.deviceType != null
              ? deviceTypeLabel(viewData.deviceType!)
              : 'laptop',
          mode: SendingStripMode.transferring,
          progress: viewData.outcome == TransferResultOutcome.success
              ? 1.0
              : 0.0,
          animate: false,
        ),
        manifest:
            viewData.manifestItems == null || viewData.manifestItems!.isEmpty
            ? null
            : ManifestTreeCard(
                items: viewData.manifestItems!,
                initiallyExpanded: true,
              ),
        footer: Row(
          children: [
            if (secondaryLabel != null && onSecondary != null) ...[
              Expanded(
                flex: 2,
                child: OutlinedButton(
                  onPressed: onSecondary,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kInk,
                    side: BorderSide(color: kBorder.withValues(alpha: 0.8)),
                    minimumSize: const Size(0, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    secondaryLabel!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: driftSans(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            if (viewData.primaryLabel.isNotEmpty && onPrimary != null)
              Expanded(
                flex: secondaryLabel != null && onSecondary != null ? 3 : 1,
                child: FilledButton(
                  onPressed: onPrimary,
                  style: FilledButton.styleFrom(
                    backgroundColor: visual.buttonColor,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    viewData.primaryLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: driftSans(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.viewData});

  final TransferResultViewData viewData;

  @override
  Widget build(BuildContext context) {
    if (viewData.outcome != TransferResultOutcome.success) {
      return const SizedBox.shrink();
    }

    final stats = <_StatItem>[
      if (viewData.totalSizeLabel != null)
        _StatItem(label: 'SIZE', value: viewData.totalSizeLabel!),
      if (viewData.durationLabel != null)
        _StatItem(label: 'TIME', value: viewData.durationLabel!),
      if (viewData.averageSpeedLabel != null)
        _StatItem(label: 'SPEED', value: viewData.averageSpeedLabel!),
    ];

    if (stats.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: kFill.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (int i = 0; i < stats.length; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                height: 24,
                color: kBorder.withValues(alpha: 0.5),
              ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    stats[i].label,
                    style: driftSans(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: kMuted,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stats[i].value,
                    style: driftSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: kInk,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatItem {
  const _StatItem({required this.label, required this.value});
  final String label;
  final String value;
}

class _TransferResultVisualData {
  const _TransferResultVisualData({
    required this.statusLabel,
    required this.accentColor,
    required this.buttonColor,
    required this.icon,
  });

  final String statusLabel;
  final Color accentColor;
  final Color buttonColor;
  final IconData icon;
}

_TransferResultVisualData _visualForOutcome(TransferResultOutcome outcome) {
  return switch (outcome) {
    TransferResultOutcome.success => const _TransferResultVisualData(
      statusLabel: 'Success',
      accentColor: Color(0xFF49B36C),
      buttonColor: Color(0xFF5FA7B7),
      icon: Icons.check_circle_rounded,
    ),
    TransferResultOutcome.cancelled => const _TransferResultVisualData(
      statusLabel: 'Cancelled',
      accentColor: Color(0xFFC0912C),
      buttonColor: Color(0xFF617B87),
      icon: Icons.do_not_disturb_on_rounded,
    ),
    TransferResultOutcome.failed => const _TransferResultVisualData(
      statusLabel: 'Failed',
      accentColor: Color(0xFFCC3333),
      buttonColor: Color(0xFFB34A4A),
      icon: Icons.error_rounded,
    ),
  };
}

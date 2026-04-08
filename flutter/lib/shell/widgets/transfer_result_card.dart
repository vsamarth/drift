import 'package:flutter/material.dart';

import '../../core/models/transfer_models.dart';
import '../../core/theme/drift_theme.dart';
import '../../state/drift_app_state.dart';
import 'transfer_layout.dart';

class TransferResultCard extends StatelessWidget {
  const TransferResultCard({
    super.key,
    required this.outcome,
    required this.title,
    required this.message,
    this.metrics,
    this.primaryLabel,
    this.onPrimary,
    this.fillBody = false,
  });

  final TransferResultOutcomeData outcome;
  final String title;
  final String message;
  final List<TransferMetricRow>? metrics;
  final String? primaryLabel;
  final VoidCallback? onPrimary;

  /// When true, uses the shared [TransferFlowLayout] for a consistent full-page
  /// experience. Otherwise, returns a compact card-style layout.
  final bool fillBody;

  @override
  Widget build(BuildContext context) {
    final visual = _visualForOutcome(outcome);

    if (fillBody) {
      return TransferFlowLayout(
        statusLabel: visual.statusLabel,
        statusColor: visual.accentColor,
        title: title,
        subtitle: message,
        illustration: DecoratedBox(
          decoration: BoxDecoration(
            color: visual.accentColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Icon(visual.icon, size: 42, color: visual.accentColor),
          ),
        ),
        manifest: metrics != null && metrics!.isNotEmpty
            ? _TransferMetricsList(metrics: metrics!)
            : null,
        footer: Row(
          children: [
            if (primaryLabel != null && onPrimary != null)
              Expanded(
                child: FilledButton(
                  onPressed: onPrimary,
                  style: FilledButton.styleFrom(
                    backgroundColor: visual.buttonColor,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(primaryLabel!),
                ),
              ),
          ],
        ),
      );
    }

    final titleStyle = driftSans(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: kInk,
      letterSpacing: -0.2,
    );
    final messageStyle = driftSans(fontSize: 13, color: kMuted, height: 1.5);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: visual.accentColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(visual.icon, size: 24, color: visual.accentColor),
          ),
          const SizedBox(height: 14),
          Text(title, style: titleStyle),
          const SizedBox(height: 4),
          Text(message, style: messageStyle),
          if (metrics != null && metrics!.isNotEmpty) ...[
            const SizedBox(height: 18),
            DecoratedBox(
              decoration: BoxDecoration(
                color: kFill.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kBorder.withValues(alpha: 0.75)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: _TransferMetricsList(metrics: metrics!),
              ),
            ),
          ],
          if (primaryLabel != null && onPrimary != null) ...[
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onPrimary,
              style: FilledButton.styleFrom(
                backgroundColor: visual.buttonColor,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(primaryLabel!),
            ),
          ],
        ],
      ),
    );
  }
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

_TransferResultVisualData _visualForOutcome(TransferResultOutcomeData outcome) {
  return switch (outcome) {
    TransferResultOutcomeData.success => const _TransferResultVisualData(
      statusLabel: 'Complete',
      accentColor: Color(0xFF49B36C),
      buttonColor: Color(0xFF4A8E9E),
      icon: Icons.check_circle_rounded,
    ),
    TransferResultOutcomeData.cancelled => const _TransferResultVisualData(
      statusLabel: 'Cancelled',
      accentColor: Color(0xFFC0912C),
      buttonColor: Color(0xFF617B87),
      icon: Icons.do_not_disturb_on_rounded,
    ),
    TransferResultOutcomeData.declined => const _TransferResultVisualData(
      statusLabel: 'Declined',
      accentColor: Color(0xFF7C8C97),
      buttonColor: Color(0xFF4A8E9E),
      icon: Icons.remove_circle_outline_rounded,
    ),
    TransferResultOutcomeData.failed => const _TransferResultVisualData(
      statusLabel: 'Failed',
      accentColor: Color(0xFFCC3333),
      buttonColor: Color(0xFFB34A4A),
      icon: Icons.error_rounded,
    ),
  };
}

class _TransferMetricsList extends StatelessWidget {
  const _TransferMetricsList({required this.metrics});

  final List<TransferMetricRow> metrics;

  @override
  Widget build(BuildContext context) {
    final labelStyle = driftSans(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: kMuted,
    );
    final valueStyle = driftSans(
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
      color: kInk,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < metrics.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: Text(metrics[i].label, style: labelStyle),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  metrics[i].value,
                  textAlign: TextAlign.end,
                  style: valueStyle,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/models/transfer_models.dart';
import '../../core/theme/drift_theme.dart';
import 'transfer_layout.dart';

enum TransferResultTone { success, error }

class TransferResultCard extends StatelessWidget {
  const TransferResultCard({
    super.key,
    required this.tone,
    required this.title,
    required this.message,
    this.metrics,
    this.primaryLabel,
    this.onPrimary,
    this.fillBody = false,
  });

  final TransferResultTone tone;
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
    final isSuccess = tone == TransferResultTone.success;
    final accentColor = isSuccess
        ? const Color(0xFF49B36C)
        : const Color(0xFFCC3333);
    final icon = isSuccess ? Icons.check_circle_rounded : Icons.error_rounded;

    if (fillBody) {
      return TransferFlowLayout(
        statusLabel: isSuccess ? 'Complete' : 'Error',
        statusColor: accentColor,
        title: title,
        subtitle: message,
        illustration: Icon(icon, size: 48, color: accentColor),
        manifest: metrics != null && metrics!.isNotEmpty
            ? _TransferMetricsList(metrics: metrics!)
            : const SizedBox.shrink(),
        footer: Row(
          children: [
            if (primaryLabel != null && onPrimary != null)
              Expanded(
                child: FilledButton(
                  onPressed: onPrimary,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF4A8E9E),
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
          Icon(icon, size: 32, color: accentColor),
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
                backgroundColor: const Color(0xFF4A8E9E),
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

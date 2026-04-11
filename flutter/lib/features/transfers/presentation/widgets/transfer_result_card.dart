import 'package:flutter/material.dart';

import '../../../../theme/drift_theme.dart';
import '../../application/result_view_data.dart';
import 'transfer_flow_layout.dart';

class TransferResultCard extends StatelessWidget {
  const TransferResultCard({
    super.key,
    required this.viewData,
    this.onPrimary,
  });

  final TransferResultViewData viewData;
  final VoidCallback? onPrimary;

  @override
  Widget build(BuildContext context) {
    final visual = _visualForOutcome(viewData.outcome);

    return SizedBox.expand(
      child: TransferFlowLayout(
        statusLabel: visual.statusLabel,
        statusColor: visual.accentColor,
        title: viewData.title,
        subtitle: viewData.message,
        explainer: _completionExplainer(viewData.metrics),
        illustration: _TransferResultIllustration(
          icon: visual.icon,
          color: visual.accentColor,
        ),
        manifest: viewData.metrics == null || viewData.metrics!.isEmpty
            ? null
            : _ResultMetricList(metrics: viewData.metrics!),
        footer: Row(
          children: [
            if (viewData.primaryLabel.isNotEmpty && onPrimary != null)
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
                  child: Text(viewData.primaryLabel),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ResultMetricList extends StatelessWidget {
  const _ResultMetricList({required this.metrics});

  final List<ResultMetric> metrics;

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
              Expanded(flex: 2, child: Text(metrics[i].label, style: labelStyle)),
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

class _TransferResultIllustration extends StatelessWidget {
  const _TransferResultIllustration({
    required this.icon,
    required this.color,
  });

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Icon(icon, size: 42, color: color),
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

Widget? _completionExplainer(List<ResultMetric>? metrics) {
  if (metrics == null || metrics.isEmpty) {
    return null;
  }

  final files = _metricValue(metrics, 'Files');
  final size = _metricValue(metrics, 'Size');
  if (files == null || size == null) {
    return null;
  }

  final count = int.tryParse(files.trim());
  if (count == null || count <= 0) {
    return null;
  }

  return Text(
    '$count file${count == 1 ? '' : 's'} finished in $size.',
    style: driftSans(fontSize: 12, color: kMuted, height: 1.4),
  );
}

String? _metricValue(List<ResultMetric> metrics, String label) {
  for (final metric in metrics) {
    if (metric.label == label) {
      return metric.value;
    }
  }
  return null;
}

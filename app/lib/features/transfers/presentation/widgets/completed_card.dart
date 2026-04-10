import 'package:flutter/material.dart';

import '../../../../theme/drift_theme.dart';
import '../../application/state.dart';
import 'transfer_flow_layout.dart';
import 'transfer_presentation_helpers.dart';

class CompletedCard extends StatelessWidget {
  const CompletedCard({
    super.key,
    required this.offer,
    required this.result,
    required this.onDone,
  });

  final TransferIncomingOffer offer;
  final TransferTransferResult result;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final senderName = displaySender(offer.sender.displayName);
    final totalSize = formatBytes(result.totalBytes);
    final metrics = <_ResultMetric>[
      _ResultMetric(label: 'From', value: senderName),
      _ResultMetric(label: 'Saved to', value: offer.destinationLabel),
      _ResultMetric(label: 'Files', value: '${result.completedFiles}'),
      _ResultMetric(label: 'Size', value: totalSize),
    ];

    return SizedBox.expand(
      child: TransferFlowLayout(
        statusLabel: 'Complete',
        statusColor: const Color(0xFF49B36C),
        title: 'Transfer complete',
        subtitle: 'Saved from $senderName.',
        explainer: Text(
          '${result.completedFiles} file${result.completedFiles == 1 ? '' : 's'} finished in $totalSize.',
          style: driftSans(fontSize: 12, color: kMuted, height: 1.4),
        ),
        illustration: _CompletionIllustration(color: const Color(0xFF49B36C)),
        manifest: _ResultMetricList(metrics: metrics),
        footer: Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: onDone,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF49B36C),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultMetric {
  const _ResultMetric({required this.label, required this.value});

  final String label;
  final String value;
}

class _ResultMetricList extends StatelessWidget {
  const _ResultMetricList({required this.metrics});

  final List<_ResultMetric> metrics;

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

class _CompletionIllustration extends StatelessWidget {
  const _CompletionIllustration({required this.color});

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
        child: Icon(Icons.check_circle_rounded, size: 42, color: color),
      ),
    );
  }
}

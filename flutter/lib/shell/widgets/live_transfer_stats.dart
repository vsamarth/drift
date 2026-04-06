import 'package:flutter/material.dart';

import '../../core/theme/drift_theme.dart';

class LiveTransferStats extends StatelessWidget {
  const LiveTransferStats({
    super.key,
    this.speedLabel,
    this.etaLabel,
    this.center = false,
  });

  final String? speedLabel;
  final String? etaLabel;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final entries = <Widget>[
      if (speedLabel != null && speedLabel!.trim().isNotEmpty)
        _StatPill(label: 'Speed', value: speedLabel!),
      if (etaLabel != null && etaLabel!.trim().isNotEmpty)
        _StatPill(label: 'ETA', value: etaLabel!),
    ];

    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      alignment: center ? WrapAlignment.center : WrapAlignment.start,
      spacing: 8,
      runSpacing: 8,
      children: entries,
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final isEta = label == 'ETA';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isEta
            ? kAccentWarmSurface.withValues(alpha: 0.18)
            : kAccentCyanHover.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isEta
              ? kAccentWarm.withValues(alpha: 0.45)
              : kAccentCyan.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: driftSans(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: kMuted,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: driftSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: kInk,
              letterSpacing: -0.15,
            ),
          ),
        ],
      ),
    );
  }
}

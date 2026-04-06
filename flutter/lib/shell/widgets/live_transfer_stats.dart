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
    final speed = speedLabel?.trim();
    final eta = etaLabel?.trim();
    if (speed == null || speed.isEmpty) {
      return const SizedBox.shrink();
    }

    final value = (eta == null || eta.isEmpty) ? speed : '$speed • $eta';

    return Row(
      mainAxisAlignment: center
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      children: [_StatPill(value: value)],
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: kAccentCyanHover.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kAccentCyan.withValues(alpha: 0.35)),
      ),
      child: Text(
        value,
        style: driftSans(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: kInk,
          letterSpacing: -0.1,
        ),
      ),
    );
  }
}

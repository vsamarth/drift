import 'package:flutter/material.dart';

import '../../core/theme/drift_theme.dart';

/// Neutral bordered surface used across send/receive panels.
class ShellSurfaceCard extends StatelessWidget {
  const ShellSurfaceCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder),
      ),
      child: child,
    );
  }
}

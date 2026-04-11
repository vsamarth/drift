import 'package:flutter/material.dart';
import '../../../../theme/drift_theme.dart';

class UtilityTransferFlowLayout extends StatelessWidget {
  const UtilityTransferFlowLayout({
    super.key,
    required this.statusLabel,
    required this.statusColor,
    required this.heroText,
    required this.subtitle,
    this.utilityBar,
    required this.progressBar,
    this.activityLine,
    this.manifest,
    required this.footer,
  });

  final String statusLabel;
  final Color statusColor;
  final String heroText;
  final String subtitle;
  final Widget? utilityBar;
  final Widget progressBar;
  final Widget? activityLine;
  final Widget? manifest;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Status Badge
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      statusLabel.toUpperCase(),
                      style: driftSans(fontSize: 11, fontWeight: FontWeight.w800, color: statusColor, letterSpacing: 1.2),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                // Hero Section
                Text(
                  heroText,
                  style: driftSans(fontSize: 42, fontWeight: FontWeight.w800, color: kInk, letterSpacing: -1.2, height: 1.0),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: driftSans(fontSize: 15, fontWeight: FontWeight.w500, color: kMuted),
                ),
                const SizedBox(height: 32),
                // Utility Bar
                if (utilityBar != null) ...[
                  utilityBar!,
                  const SizedBox(height: 16),
                ],
                // Progress Bar
                progressBar,
                const SizedBox(height: 20),
                // Activity Line
                if (activityLine != null) activityLine!,
                if (activityLine != null) const SizedBox(height: 32),
                // Manifest (Flat list)
                if (manifest != null) manifest!,
              ],
            ),
          ),
        ),
        // Integrated Footer
        Padding(
          padding: const EdgeInsets.all(24),
          child: footer,
        ),
      ],
    );
  }
}

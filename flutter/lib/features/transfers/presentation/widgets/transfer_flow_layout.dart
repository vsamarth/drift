import 'package:flutter/material.dart';

import '../../../../theme/drift_theme.dart';

class TransferFlowLayout extends StatelessWidget {
  const TransferFlowLayout({
    super.key,
    required this.statusLabel,
    required this.statusColor,
    required this.subtitle,
    this.explainer,
    required this.illustration,
    this.manifest,
    required this.footer,
  });

  final String statusLabel;
  final Color statusColor;
  final String subtitle;
  final Widget? explainer;
  final Widget illustration;
  final Widget? manifest;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        statusLabel.toUpperCase(),
                        style: driftSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: statusColor,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                illustration,
                const SizedBox(height: 24),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: driftSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: kMuted,
                    height: 1.4,
                  ),
                ),
                if (explainer != null) ...[
                  const SizedBox(height: 24),
                  explainer!,
                ],
                const SizedBox(height: 48),
                if (manifest != null) ...[
                  manifest!,
                  const SizedBox(height: 32),
                ],
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          decoration: BoxDecoration(
            color: kBg,
            border: Border(
              top: BorderSide(color: kBorder.withValues(alpha: 0.5)),
            ),
          ),
          child: footer,
        ),
      ],
    );
  }
}

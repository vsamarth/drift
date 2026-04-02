import 'package:flutter/material.dart';

import '../../core/theme/drift_theme.dart';

/// A shared layout for transfer flows (Send/Receive).
/// Includes a scrollable body with header, illustration, and manifest card,
/// plus a sticky footer for actions.
class TransferFlowLayout extends StatelessWidget {
  const TransferFlowLayout({
    super.key,
    required this.statusLabel,
    required this.statusColor,
    required this.title,
    required this.subtitle,
    this.explainer,
    required this.illustration,
    required this.manifest,
    required this.footer,
  });

  final String statusLabel;
  final Color statusColor;
  final String title;
  final String subtitle;
  final Widget? explainer;
  final Widget illustration;
  final Widget manifest;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header Block
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
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
                          const SizedBox(width: 6),
                          Text(
                            statusLabel,
                            style: driftSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: statusColor,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  title,
                  style: driftSans(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: kInk,
                    letterSpacing: -0.6,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  subtitle,
                  style: driftSans(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: kMuted,
                    height: 1.4,
                  ),
                ),
                if (explainer != null) ...[
                  const SizedBox(height: 12),
                  explainer!,
                ],
                const SizedBox(height: 20),
                // Illustration Block
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 100),
                    child: illustration,
                  ),
                ),
                const SizedBox(height: 24),
                // Manifest Card
                Container(
                  decoration: BoxDecoration(
                    color: kSurface2,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: kBorder.withValues(alpha: 0.8)),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
                        child: manifest,
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
        // Sticky Footer
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: kBg,
            border: Border(top: BorderSide(color: kBorder.withValues(alpha: 0.5))),
          ),
          child: footer,
        ),
      ],
    );
  }
}

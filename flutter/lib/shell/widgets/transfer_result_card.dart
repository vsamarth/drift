import 'package:flutter/material.dart';

import '../../core/theme/drift_theme.dart';

enum TransferResultTone { success, error }

class TransferResultCard extends StatelessWidget {
  const TransferResultCard({
    super.key,
    required this.tone,
    required this.title,
    required this.message,
    this.primaryLabel,
    this.onPrimary,
    this.fillBody = false,
  });

  final TransferResultTone tone;
  final String title;
  final String message;
  final String? primaryLabel;
  final VoidCallback? onPrimary;

  /// When true, fills the parent height, centers status above the fold, and
  /// pins the primary action to the bottom (full width).
  final bool fillBody;

  @override
  Widget build(BuildContext context) {
    final isSuccess = tone == TransferResultTone.success;
    final accentColor =
        isSuccess ? const Color(0xFF49B36C) : const Color(0xFFCC3333);
    final icon = isSuccess ? Icons.check_circle_rounded : Icons.error_rounded;

    final titleStyle = driftSans(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: kInk,
      letterSpacing: -0.2,
    );
    final messageStyle = driftSans(
      fontSize: 13,
      color: kMuted,
      height: 1.5,
    );

    final statusBlock = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          fillBody ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 32, color: accentColor),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: fillBody ? TextAlign.center : TextAlign.start,
          style: titleStyle,
        ),
        const SizedBox(height: 4),
        Text(
          message,
          textAlign: fillBody ? TextAlign.center : TextAlign.start,
          style: messageStyle,
        ),
      ],
    );

    if (!fillBody) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            statusBlock,
            if (primaryLabel != null && onPrimary != null) ...[
              const SizedBox(height: 24),
              FilledButton(onPressed: onPrimary, child: Text(primaryLabel!)),
            ],
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [statusBlock],
            ),
          ),
          if (primaryLabel != null && onPrimary != null) ...[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onPrimary,
              child: Text(primaryLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

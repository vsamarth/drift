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
  });

  final TransferResultTone tone;
  final String title;
  final String message;
  final String? primaryLabel;
  final VoidCallback? onPrimary;

  @override
  Widget build(BuildContext context) {
    final isSuccess = tone == TransferResultTone.success;
    final fgColor = isSuccess
        ? const Color(0xFF1A6B3A)
        : const Color(0xFFAA2222);
    final bgColor = isSuccess
        ? const Color(0xFFF2FAF5)
        : const Color(0xFFFFF0F0);
    final borderColor = isSuccess
        ? const Color(0xFFCCE8D8)
        : const Color(0xFFEECCCC);
    final icon = isSuccess ? Icons.check_circle_rounded : Icons.error_rounded;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 28, color: fgColor),
          const SizedBox(height: 14),
          Text(
            title,
            style: driftSans(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: fgColor,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            message,
            style: driftSans(
              fontSize: 13,
              color: fgColor.withValues(alpha: 0.70),
              height: 1.5,
            ),
          ),
          if (primaryLabel != null && onPrimary != null) ...[
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onPrimary,
              style: FilledButton.styleFrom(
                backgroundColor: fgColor,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: driftSans(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              child: Text(primaryLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

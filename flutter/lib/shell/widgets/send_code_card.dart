import 'package:flutter/material.dart';

import '../../core/theme/drift_theme.dart';
import '../../state/drift_controller.dart';
import 'preview_list.dart';
import 'shell_surface_card.dart';

class SendCodeCard extends StatelessWidget {
  const SendCodeCard({
    super.key,
    required this.controller,
    required this.title,
    required this.status,
    required this.primaryLabel,
    required this.onPrimary,
  });

  final DriftController controller;
  final String title;
  final String status;
  final String primaryLabel;
  final VoidCallback onPrimary;

  String _fmt(String? raw) {
    if (raw == null || raw.length != 6) return raw ?? '';
    return '${raw.substring(0, 3)} ${raw.substring(3)}';
  }

  @override
  Widget build(BuildContext context) {
    final summary = controller.sendSummary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: kCodeBg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: driftSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.45),
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                status,
                style: driftSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.90),
                ),
              ),
              const SizedBox(height: 22),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 20,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Text(
                  _fmt(summary?.code),
                  textAlign: TextAlign.center,
                  style: driftMono(
                    fontSize: 38,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 10,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '${summary?.itemCount ?? 0} items · ${summary?.totalSize ?? ''} · ${summary?.expiresAt ?? ''}',
                style: driftSans(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.40),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onPrimary,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: kInk,
                    minimumSize: const Size(double.infinity, 44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: driftSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Text(primaryLabel),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ShellSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Files', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              PreviewList(
                items: controller.visibleSendItems,
                hiddenItemCount: controller.hiddenSendItemCount,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/theme/drift_theme.dart';
import '../../state/drift_controller.dart';
import 'receive_code_field.dart';
import 'shell_surface_card.dart';

class ReceiveEntryCard extends StatelessWidget {
  const ReceiveEntryCard({
    super.key,
    required this.controller,
    required this.title,
    this.helper,
    this.errorText,
    this.height,
  });

  final DriftController controller;
  final String title;
  final String? helper;
  final String? errorText;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null;

    return SizedBox(
      height: height,
      child: ShellSurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            if (helper != null) ...[
              const SizedBox(height: 4),
              Text(helper!, style: Theme.of(context).textTheme.bodyMedium),
            ],
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ReceiveCodeField(
                    key: const ValueKey<String>('receive-code-field'),
                    code: controller.receiveCode,
                    onChanged: controller.updateReceiveCode,
                    onSubmitted: (_) => controller.previewReceiveOffer(),
                    hasError: hasError,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const ValueKey<String>('receive-submit'),
                  onPressed: controller.previewReceiveOffer,
                  child: const Text('Receive'),
                ),
              ],
            ),
            if (hasError) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF0F0),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFEECCCC)),
                ),
                child: Text(
                  errorText!,
                  style: driftSans(
                    fontSize: 13,
                    color: const Color(0xFFAA2222),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

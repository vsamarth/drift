import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/drift_theme.dart';
import '../../state/drift_providers.dart';
import 'receive_code_field.dart';

class ReceiveEntryCard extends ConsumerWidget {
  const ReceiveEntryCard({
    super.key,
    required this.title,
    this.helper,
    this.errorText,
    this.height,
  });

  final String title;
  final String? helper;
  final String? errorText;
  final double? height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(driftAppNotifierProvider);
    final notifier = ref.read(driftAppNotifierProvider.notifier);
    final hasError = errorText != null;

    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
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
                    code: state.receiveCode,
                    onChanged: notifier.updateReceiveCode,
                    onSubmitted: (_) => notifier.previewReceiveOffer(),
                    hasError: hasError,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const ValueKey<String>('receive-submit'),
                  onPressed: notifier.previewReceiveOffer,
                  child: const Text('Receive'),
                ),
              ],
            ),
            if (hasError) ...[
              const SizedBox(height: 10),
              Text(
                errorText!,
                style: driftSans(
                  fontSize: 13,
                  color: const Color(0xFFCC3333),
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

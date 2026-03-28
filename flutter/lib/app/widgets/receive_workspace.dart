import 'package:flutter/material.dart';

import '../drift_controller.dart';
import '../models.dart';

class ReceiveWorkspace extends StatelessWidget {
  const ReceiveWorkspace({super.key, required this.controller});

  final DriftController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Receive', style: theme.textTheme.headlineLarge),
            const SizedBox(height: 8),
            Text(
              'Enter a short code, review the incoming manifest, and decide inline where it should land.',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            _ReceiveEntryPanel(controller: controller),
            const SizedBox(height: 20),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _ReceivePreviewPanel(controller: controller)),
                  const SizedBox(width: 18),
                  Expanded(child: _ReceiveSummaryPanel(controller: controller)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiveEntryPanel extends StatelessWidget {
  const _ReceiveEntryPanel({required this.controller});

  final DriftController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ReceiveCodeField(
              key: const ValueKey('receive-code-field'),
              code: controller.receiveCode,
              onChanged: controller.updateReceiveCode,
            ),
          ),
          const SizedBox(width: 16),
          FilledButton(
            onPressed: controller.previewReceiveOffer,
            child: const Text('Preview Offer'),
          ),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: controller.loadReceiveError,
            child: const Text('Expired Example'),
          ),
        ],
      ),
    );
  }
}

class _ReceiveCodeField extends StatefulWidget {
  const _ReceiveCodeField({
    super.key,
    required this.code,
    required this.onChanged,
  });

  final String code;
  final ValueChanged<String> onChanged;

  @override
  State<_ReceiveCodeField> createState() => _ReceiveCodeFieldState();
}

class _ReceiveCodeFieldState extends State<_ReceiveCodeField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.code);
  }

  @override
  void didUpdateWidget(covariant _ReceiveCodeField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.code != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.code,
        selection: TextSelection.collapsed(offset: widget.code.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onChanged: widget.onChanged,
      textCapitalization: TextCapitalization.characters,
      decoration: const InputDecoration(
        labelText: 'Short code',
        hintText: 'AB2CD3',
      ),
    );
  }
}

class _ReceivePreviewPanel extends StatelessWidget {
  const _ReceivePreviewPanel({required this.controller});

  final DriftController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stage = controller.receiveStage;
    final items = controller.receiveItems;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Manifest Preview', style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(switch (stage) {
              TransferStage.idle =>
                'Enter a code to preview the files before accepting.',
              TransferStage.review =>
                'Review the incoming structure before saving anything.',
              TransferStage.completed =>
                'The accepted offer remains visible so the flow is easy to revisit.',
              TransferStage.error =>
                controller.receiveErrorText ??
                    'There was a problem loading the preview.',
              _ => 'Receive mode keeps all important details inline.',
            }, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 18),
            if (items.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    stage == TransferStage.error
                        ? controller.receiveErrorText ??
                              'Unable to preview this offer.'
                        : 'Nothing to review yet. Try the sample code `AB2CD3`.',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F6F8),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.description_rounded,
                            size: 20,
                            color: Color(0xFF48697C),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  item.path,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          Text(item.size, style: theme.textTheme.labelLarge),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReceiveSummaryPanel extends StatelessWidget {
  const _ReceiveSummaryPanel({required this.controller});

  final DriftController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = controller.receiveSummary;
    final stage = controller.receiveStage;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F5EE),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Destination & Status', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              summary?.statusMessage ?? _fallbackMessage(stage),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Save destination', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 6),
                  Text(
                    summary?.destinationLabel ?? '~/Downloads/Drift',
                    style: theme.textTheme.titleLarge,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (summary != null) ...[
              Text(
                '${summary.itemCount} items • ${summary.totalSize}',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(summary.expiresAt, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              Text(
                'Offer code ${summary.code}',
                style: theme.textTheme.bodyMedium,
              ),
            ],
            const Spacer(),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: switch (stage) {
                TransferStage.review => [
                  FilledButton(
                    onPressed: controller.acceptReceiveOffer,
                    child: const Text('Accept Transfer'),
                  ),
                  OutlinedButton(
                    onPressed: controller.declineReceiveOffer,
                    child: const Text('Decline'),
                  ),
                ],
                TransferStage.completed => [
                  OutlinedButton(
                    onPressed: controller.declineReceiveOffer,
                    child: const Text('Start Over'),
                  ),
                ],
                TransferStage.error => [
                  OutlinedButton(
                    onPressed: controller.declineReceiveOffer,
                    child: const Text('Clear Error'),
                  ),
                ],
                _ => [
                  FilledButton(
                    onPressed: controller.previewReceiveOffer,
                    child: const Text('Preview with Current Code'),
                  ),
                ],
              },
            ),
          ],
        ),
      ),
    );
  }

  String _fallbackMessage(TransferStage stage) {
    return switch (stage) {
      TransferStage.idle =>
        'Incoming offers stay quiet until you enter a short code.',
      TransferStage.error =>
        controller.receiveErrorText ??
            'There was a problem previewing the current code.',
      TransferStage.completed =>
        'Accepted transfers stay visible until you start over.',
      _ => 'Review manifests and choose when to accept.',
    };
  }
}

import 'package:flutter/material.dart';

import '../drift_controller.dart';
import '../models.dart';

class SendWorkspace extends StatelessWidget {
  const SendWorkspace({super.key, required this.controller});

  final DriftController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = controller.sendSummary;

    return Card(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compactLayout =
              constraints.maxWidth < 860 || constraints.maxHeight < 720;

          final detailsSection = compactLayout
              ? Column(
                  children: [
                    SizedBox(
                      height: 320,
                      child: _SelectionPanel(
                        stage: controller.sendStage,
                        items: controller.sendItems,
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 320,
                      child: _SendSummaryPanel(
                        stage: controller.sendStage,
                        summary: summary,
                        onMarkWaiting: controller.markSendWaiting,
                        onComplete: controller.completeSendDemo,
                        onError: controller.failSendDemo,
                        onReset: controller.clearSendFlow,
                      ),
                    ),
                  ],
                )
              : Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _SelectionPanel(
                          stage: controller.sendStage,
                          items: controller.sendItems,
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: _SendSummaryPanel(
                          stage: controller.sendStage,
                          summary: summary,
                          onMarkWaiting: controller.markSendWaiting,
                          onComplete: controller.completeSendDemo,
                          onError: controller.failSendDemo,
                          onReset: controller.clearSendFlow,
                        ),
                      ),
                    ],
                  ),
                );

          final mainContent = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Send', style: theme.textTheme.headlineLarge),
              const SizedBox(height: 8),
              Text(
                'Drop files or folders, mint a short code, and keep the whole flow clear in one place.',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              _SendDropZone(controller: controller),
              const SizedBox(height: 20),
              detailsSection,
            ],
          );

          return Padding(
            padding: const EdgeInsets.all(28),
            child: compactLayout
                ? SingleChildScrollView(child: mainContent)
                : mainContent,
          );
        },
      ),
    );
  }
}

class _SendDropZone extends StatelessWidget {
  const _SendDropZone({required this.controller});

  final DriftController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final highlighted =
        controller.sendDropActive ||
        controller.sendStage == TransferStage.collecting;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            gradient: highlighted
                ? const LinearGradient(
                    colors: [Color(0xFFE7F1ED), Color(0xFFF4F7F2)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : const LinearGradient(
                    colors: [Color(0xFFFDFCF9), Color(0xFFF6F4EE)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: highlighted
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
              width: highlighted ? 1.4 : 1,
            ),
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DropZoneHeader(highlighted: highlighted, theme: theme),
                    const SizedBox(height: 20),
                    _DropZoneActions(controller: controller, compact: true),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: _DropZoneHeader(
                        highlighted: highlighted,
                        theme: theme,
                      ),
                    ),
                    const SizedBox(width: 20),
                    _DropZoneActions(controller: controller, compact: false),
                  ],
                ),
        );
      },
    );
  }
}

class _DropZoneHeader extends StatelessWidget {
  const _DropZoneHeader({required this.highlighted, required this.theme});

  final bool highlighted;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.86),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Icon(
            Icons.upload_file_rounded,
            size: 32,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                highlighted
                    ? 'Drop zone is live and ready.'
                    : 'Drag files or folders here.',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                highlighted
                    ? 'The UI-only MVP stages a realistic sample selection so we can tune the flow before wiring file access.'
                    : 'For now, the desktop MVP uses mock data to preview how transfers will feel on macOS.',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DropZoneActions extends StatelessWidget {
  const _DropZoneActions({required this.controller, required this.compact});

  final DriftController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final actions = [
      FilledButton.icon(
        onPressed: controller.activateSendDropTarget,
        icon: const Icon(Icons.touch_app_rounded),
        label: const Text('Simulate Drop'),
      ),
      compact ? const SizedBox(height: 12) : const SizedBox(width: 12),
      OutlinedButton.icon(
        onPressed: controller.generateOffer,
        icon: const Icon(Icons.folder_open_rounded),
        label: const Text('Load Sample Files'),
      ),
    ];

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: actions,
      );
    }

    return Row(mainAxisSize: MainAxisSize.min, children: actions);
  }
}

class _SelectionPanel extends StatelessWidget {
  const _SelectionPanel({required this.stage, required this.items});

  final TransferStage stage;
  final List<TransferItemViewData> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compactHeight = constraints.maxHeight < 260;

          final description = Text(switch (stage) {
            TransferStage.idle =>
              'Nothing staged yet. Start with a drop or sample selection.',
            TransferStage.collecting =>
              'Mock items are staged so we can preview the desktop collection state.',
            TransferStage.ready ||
            TransferStage.waiting ||
            TransferStage.completed ||
            TransferStage.error =>
              'These items match the manifest that will later be sent over the real connection.',
            TransferStage.review => 'Review state is reserved for receiving.',
          }, style: theme.textTheme.bodyMedium);

          final listBody = items.isEmpty
              ? Center(
                  child: Text(
                    'Use “Simulate Drop” to preview the collecting state.',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                )
              : AnimatedOpacity(
                  duration: const Duration(milliseconds: 220),
                  opacity: 1,
                  child: ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final folder = item.kind == TransferItemKind.folder;
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: folder
                              ? const Color(0xFFF6F1E4)
                              : const Color(0xFFF3F6F8),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              folder
                                  ? Icons.folder_copy_rounded
                                  : Icons.insert_drive_file_rounded,
                              size: 20,
                              color: folder
                                  ? const Color(0xFF7A6130)
                                  : const Color(0xFF496778),
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
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(item.size, style: theme.textTheme.labelLarge),
                          ],
                        ),
                      );
                    },
                  ),
                );

          return Padding(
            padding: const EdgeInsets.all(22),
            child: compactHeight
                ? SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Selection', style: theme.textTheme.titleLarge),
                        const SizedBox(height: 6),
                        description,
                        const SizedBox(height: 18),
                        SizedBox(height: 180, child: listBody),
                      ],
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Selection', style: theme.textTheme.titleLarge),
                      const SizedBox(height: 6),
                      description,
                      const SizedBox(height: 18),
                      Expanded(child: listBody),
                    ],
                  ),
          );
        },
      ),
    );
  }
}

class _SendSummaryPanel extends StatelessWidget {
  const _SendSummaryPanel({
    required this.stage,
    required this.summary,
    required this.onMarkWaiting,
    required this.onComplete,
    required this.onError,
    required this.onReset,
  });

  final TransferStage stage;
  final TransferSummaryViewData? summary;
  final VoidCallback onMarkWaiting;
  final VoidCallback onComplete;
  final VoidCallback onError;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF1D2529),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Offer Status',
              style: theme.textTheme.titleLarge?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              _headlineForStage(stage),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: Colors.white.withValues(alpha: 0.82),
              ),
            ),
            const SizedBox(height: 20),
            if (summary == null)
              Expanded(
                child: Center(
                  child: Text(
                    'Generate a sample offer to reveal the short code, expiry, and transfer details.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.74),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        summary!.code,
                        style: theme.textTheme.headlineLarge?.copyWith(
                          color: Colors.white,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _MetricCard(
                            label: 'Items',
                            value: summary!.itemCount.toString(),
                          ),
                          _MetricCard(
                            label: 'Total size',
                            value: summary!.totalSize,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        summary!.expiresAt,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.74),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        summary!.statusMessage,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.88),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: switch (stage) {
                          TransferStage.ready => [
                            FilledButton(
                              onPressed: onMarkWaiting,
                              child: const Text('Mark Waiting'),
                            ),
                            OutlinedButton(
                              onPressed: onReset,
                              child: const Text('Reset'),
                            ),
                          ],
                          TransferStage.waiting => [
                            FilledButton(
                              onPressed: onComplete,
                              child: const Text('Complete Demo'),
                            ),
                            OutlinedButton(
                              onPressed: onError,
                              child: const Text('Show Error'),
                            ),
                          ],
                          TransferStage.completed || TransferStage.error => [
                            OutlinedButton(
                              onPressed: onReset,
                              child: const Text('Start New Transfer'),
                            ),
                          ],
                          _ => [
                            FilledButton(
                              onPressed: onMarkWaiting,
                              child: const Text('Preview Waiting State'),
                            ),
                          ],
                        },
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _headlineForStage(TransferStage stage) {
    return switch (stage) {
      TransferStage.idle => 'No offer yet. Build the flow from the drop zone.',
      TransferStage.collecting =>
        'Files are staged and ready for a short code.',
      TransferStage.ready =>
        'Offer ready. Share the short code with your receiver.',
      TransferStage.waiting =>
        'Waiting for the receiver to accept and connect.',
      TransferStage.review => 'Review is only used on the receive side.',
      TransferStage.completed => 'Transfer finished cleanly.',
      TransferStage.error => 'This sample run ended with a clear inline error.',
    };
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 128,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.68),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/drift_providers.dart';
import '../shell_routing.dart';
import 'receive_idle_card.dart';
import 'receive_receiving_card.dart';
import 'receive_review_card.dart';
import 'send_code_card.dart';
import 'send_drop_panel.dart';
import 'send_selected_card.dart';
import 'transfer_result_card.dart';

/// Picks the main body for the current [ShellView] (full-height vs scrollable).
class ShellStateContent extends ConsumerWidget {
  const ShellStateContent({
    super.key,
    required this.view,
    required this.availableHeight,
    this.overrideChild,
  });

  final ShellView view;
  final double availableHeight;
  final Widget? overrideChild;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (overrideChild != null) {
      return SizedBox(
        height: availableHeight,
        width: double.infinity,
        child: overrideChild,
      );
    }

    final notifier = ref.read(driftAppNotifierProvider.notifier);
    final state = ref.watch(driftAppNotifierProvider);

    return switch (view) {
      ShellView.sendIdle => SendDropPanel(
        onChooseFiles: notifier.pickSendItems,
        onDropPaths: notifier.acceptDroppedSendItems,
        height: availableHeight,
      ),
      ShellView.receiveIdle => SizedBox(
        height: availableHeight,
        width: double.infinity,
        child: const ReceiveIdleCard(),
      ),
      ShellView.sendSelected => SizedBox(
        height: availableHeight,
        width: double.infinity,
        child: const SendSelectedCard(),
      ),
      ShellView.sendReady => SizedBox(
        height: availableHeight,
        width: double.infinity,
        child: SendCodeCard(
          fillBody: true,
          title: 'Sending',
          status: state.sendSummary?.statusMessage ?? 'Request sent',
        ),
      ),
      ShellView.sendWaiting => SizedBox(
        height: availableHeight,
        width: double.infinity,
        child: SendCodeCard(
          fillBody: true,
          title: 'Sending',
          status:
              state.sendSummary?.statusMessage ?? 'Waiting for confirmation.',
        ),
      ),
      ShellView.sendCompleted => SizedBox(
        height: availableHeight,
        width: double.infinity,
        child: TransferResultCard(
          fillBody: true,
          tone: TransferResultTone.success,
          title: 'Transfer complete',
          message:
              state.sendSummary?.statusMessage ?? 'Files sent successfully',
          metrics: state.sendCompletionMetrics,
          primaryLabel: 'Done',
          onPrimary: notifier.resetShell,
        ),
      ),
      ShellView.sendError => SizedBox(
        height: availableHeight,
        width: double.infinity,
        child: TransferResultCard(
          fillBody: true,
          tone: TransferResultTone.error,
          title: 'Transfer failed',
          message:
              state.sendSummary?.statusMessage ??
              'This transfer did not finish.',
        ),
      ),
      ShellView.receiveReview => SizedBox(
        height: availableHeight,
        width: double.infinity,
        child: const ReceiveReviewCard(),
      ),
      ShellView.receiveReceiving => SizedBox(
        height: availableHeight,
        width: double.infinity,
        child: const ReceiveReceivingCard(),
      ),
      ShellView.receiveCompleted => SizedBox(
        height: availableHeight,
        width: double.infinity,
        child: TransferResultCard(
          fillBody: true,
          tone: TransferResultTone.success,
          title: 'Files saved',
          message: state.receiveSummary?.statusMessage ?? 'Files saved',
          metrics: state.receiveCompletionMetrics,
          primaryLabel: 'Done',
          onPrimary: notifier.resetShell,
        ),
      ),
    };
  }
}

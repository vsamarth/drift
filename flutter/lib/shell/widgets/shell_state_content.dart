import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/drift_providers.dart';
import '../shell_routing.dart';
import 'receive_entry_card.dart';
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
  });

  final ShellView view;
  final double availableHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(driftAppNotifierProvider);
    final notifier = ref.read(driftAppNotifierProvider.notifier);

    return switch (view) {
      ShellView.sendIdle => SendDropPanel(
        onChooseFiles: notifier.pickSendItems,
        onDropPaths: notifier.acceptDroppedSendItems,
        height: availableHeight,
      ),
      ShellView.receiveEntry => ReceiveEntryCard(
        title: 'Receive files',
        helper: 'Enter the code from the sending device',
        height: availableHeight,
      ),
      ShellView.receiveError => ReceiveEntryCard(
        title: 'Receive files',
        helper: 'Enter a valid code to continue',
        errorText: state.receiveErrorText,
        height: availableHeight,
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
          message: state.receiveSummary?.statusMessage ?? 'Saved to Downloads',
          metrics: state.receiveCompletionMetrics,
          primaryLabel: 'Done',
          onPrimary: notifier.resetShell,
        ),
      ),
    };
  }
}

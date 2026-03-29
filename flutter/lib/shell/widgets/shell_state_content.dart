import 'package:flutter/material.dart';

import '../../state/drift_controller.dart';
import '../shell_routing.dart';
import 'receive_entry_card.dart';
import 'receive_review_card.dart';
import 'send_code_card.dart';
import 'send_drop_panel.dart';
import 'send_selected_card.dart';
import 'transfer_result_card.dart';

/// Picks the main body for the current [ShellView] (full-height vs scrollable).
class ShellStateContent extends StatelessWidget {
  const ShellStateContent({
    super.key,
    required this.controller,
    required this.view,
    required this.availableHeight,
    this.idleWindowHovering = false,
  });

  final DriftController controller;
  final ShellView view;
  final double availableHeight;
  final bool idleWindowHovering;

  @override
  Widget build(BuildContext context) {
    return switch (view) {
      ShellView.sendIdle => SendDropPanel(
        onChooseFiles: controller.pickSendItems,
        onDropPaths: controller.acceptDroppedSendItems,
        height: availableHeight,
        windowHovering: idleWindowHovering,
      ),
      ShellView.receiveEntry => ReceiveEntryCard(
        controller: controller,
        title: 'Receive files',
        helper: 'Enter the code from the sending device',
        height: availableHeight,
      ),
      ShellView.receiveError => ReceiveEntryCard(
        controller: controller,
        title: 'Receive files',
        helper: 'Enter a valid code to continue',
        errorText: controller.receiveErrorText,
        height: availableHeight,
      ),
      ShellView.sendSelected => SizedBox(
        height: availableHeight,
        width: double.infinity,
        child: SendSelectedCard(controller: controller),
      ),
      ShellView.sendReady => SizedBox(
        height: availableHeight,
        width: double.infinity,
        child: SendCodeCard(
          fillBody: true,
          controller: controller,
          title: 'Sending',
          status: controller.sendSummary?.statusMessage ?? 'Request sent',
        ),
      ),
      ShellView.sendWaiting => SizedBox(
        height: availableHeight,
        width: double.infinity,
        child: SendCodeCard(
          fillBody: true,
          controller: controller,
          title: 'Sending',
          status:
              controller.sendSummary?.statusMessage ??
              'Waiting for confirmation.',
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
              controller.sendSummary?.statusMessage ??
              'Files sent successfully',
          metrics: controller.sendCompletionMetrics,
          primaryLabel: 'Send more files',
          onPrimary: controller.resetShell,
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
              controller.sendSummary?.statusMessage ??
              'This transfer did not finish.',
        ),
      ),
      ShellView.receiveReview => SizedBox(
        height: availableHeight,
        width: double.infinity,
        child: ReceiveReviewCard(controller: controller),
      ),
      ShellView.receiveReceiving => SizedBox(
        height: availableHeight,
        width: double.infinity,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              controller.receiveSummary?.statusMessage ?? 'Receiving files…',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
      ShellView.receiveCompleted => SizedBox(
        height: availableHeight,
        width: double.infinity,
        child: TransferResultCard(
          fillBody: true,
          tone: TransferResultTone.success,
          title: 'Files saved',
          message:
              controller.receiveSummary?.statusMessage ?? 'Saved to Downloads',
          metrics: controller.receiveCompletionMetrics,
          primaryLabel: 'Done',
          onPrimary: controller.resetShell,
        ),
      ),
    };
  }
}

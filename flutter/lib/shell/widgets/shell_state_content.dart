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
  });

  final DriftController controller;
  final ShellView view;
  final double availableHeight;

  static Widget _scrollable(Widget child) => SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    return switch (view) {
      ShellView.sendIdle => SendDropPanel(
        onChooseFiles: controller.activateSendDropTarget,
        height: availableHeight,
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
      ShellView.sendSelected => _scrollable(SendSelectedCard(controller: controller)),
      ShellView.sendReady => _scrollable(
        SendCodeCard(
          controller: controller,
          title: 'Ready to send',
          status: 'Share this code with the receiving device',
          primaryLabel: 'Copy code',
          onPrimary: controller.markSendWaiting,
        ),
      ),
      ShellView.sendWaiting => _scrollable(
        SendCodeCard(
          controller: controller,
          title: 'Waiting for receiver…',
          status: 'Enter this code on the other device',
          primaryLabel: 'Mark as done',
          onPrimary: controller.completeSendDemo,
        ),
      ),
      ShellView.sendCompleted => _scrollable(
        TransferResultCard(
          tone: TransferResultTone.success,
          title: 'Transfer complete',
          message: controller.sendSummary?.statusMessage ?? 'Files sent successfully',
          primaryLabel: 'Send more files',
          onPrimary: controller.resetShell,
        ),
      ),
      ShellView.sendError => _scrollable(
        TransferResultCard(
          tone: TransferResultTone.error,
          title: 'Transfer failed',
          message: controller.sendSummary?.statusMessage ?? 'This transfer did not finish.',
          primaryLabel: 'Try again',
          onPrimary: controller.resetShell,
        ),
      ),
      ShellView.receiveReview => _scrollable(ReceiveReviewCard(controller: controller)),
      ShellView.receiveCompleted => _scrollable(
        TransferResultCard(
          tone: TransferResultTone.success,
          title: 'Files saved',
          message: controller.receiveSummary?.statusMessage ?? 'Saved to Downloads',
          primaryLabel: 'Done',
          onPrimary: controller.resetShell,
        ),
      ),
    };
  }
}

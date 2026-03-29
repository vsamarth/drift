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

  static Widget _scrollable(Widget child) => SingleChildScrollView(
    physics: const BouncingScrollPhysics(),
    child: child,
  );

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
      ShellView.sendSelected => _scrollable(
        SendSelectedCard(controller: controller),
      ),
      ShellView.sendReady => _scrollable(
        SendCodeCard(
          controller: controller,
          title: 'Connecting',
          status:
              controller.sendSummary?.statusMessage ??
              'Starting transfer to ${controller.sendDestinationLabel ?? 'the other device'}.',
        ),
      ),
      ShellView.sendWaiting => _scrollable(
        SendCodeCard(
          controller: controller,
          title: 'Sending',
          status:
              controller.sendSummary?.statusMessage ??
              'Waiting for ${controller.sendDestinationLabel ?? 'the other device'} to finish connecting.',
        ),
      ),
      ShellView.sendCompleted => _scrollable(
        TransferResultCard(
          tone: TransferResultTone.success,
          title: 'Transfer complete',
          message:
              controller.sendSummary?.statusMessage ??
              'Files sent successfully',
          primaryLabel: 'Send more files',
          onPrimary: controller.resetShell,
        ),
      ),
      ShellView.sendError => _scrollable(
        TransferResultCard(
          tone: TransferResultTone.error,
          title: 'Transfer failed',
          message:
              controller.sendSummary?.statusMessage ??
              'This transfer did not finish.',
        ),
      ),
      ShellView.receiveReview => _scrollable(
        ReceiveReviewCard(controller: controller),
      ),
      ShellView.receiveCompleted => _scrollable(
        TransferResultCard(
          tone: TransferResultTone.success,
          title: 'Files saved',
          message:
              controller.receiveSummary?.statusMessage ?? 'Saved to Downloads',
          primaryLabel: 'Done',
          onPrimary: controller.resetShell,
        ),
      ),
    };
  }
}

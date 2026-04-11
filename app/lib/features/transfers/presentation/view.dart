import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/controller.dart';
import '../application/service.dart';
import '../application/state.dart';
import 'widgets/receiving_card.dart';
import 'widgets/offer_card.dart';
import 'widgets/empty_card.dart';
import 'widgets/transfer_result_card.dart';

class TransfersFeature extends ConsumerWidget {
  const TransfersFeature({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(transfersViewStateProvider);
    final animateReview = ref.watch(transferReviewAnimationProvider);
    return SizedBox.expand(
      child: switch (state.phase) {
        TransferSessionPhase.offerPending => OfferCard(
          offer: state.incomingOffer!,
          animate: animateReview,
          onAccept: () =>
              ref.read(transfersServiceProvider.notifier).acceptOffer(),
          onDecline: () =>
              ref.read(transfersServiceProvider.notifier).declineOffer(),
        ),
        TransferSessionPhase.receiving => ReceivingCard(
          offer: state.incomingOffer!,
          progress: state.progress!,
          animate: animateReview,
          onCancel: () =>
              ref.read(transfersServiceProvider.notifier).cancelTransfer(),
        ),
        TransferSessionPhase.completed =>
          _buildTransferResultCard(
            outcome: TransferResultOutcome.success,
            offer: state.incomingOffer!,
            result: state.result!,
            message: state.incomingOffer?.statusMessage ?? 'Transfer complete',
            title: 'Files saved',
            onDone: () =>
                ref.read(transfersServiceProvider.notifier).dismissTransferResult(),
          ),
        TransferSessionPhase.cancelled =>
          _buildTransferResultCard(
            outcome: TransferResultOutcome.cancelled,
            offer: state.incomingOffer!,
            result: state.result,
            message:
                state.errorMessage ??
                'Drift stopped receiving before all files were saved.',
            title: 'Receive cancelled',
            onDone: () =>
                ref.read(transfersServiceProvider.notifier).dismissTransferResult(),
          ),
        TransferSessionPhase.failed =>
          _buildTransferResultCard(
            outcome: TransferResultOutcome.failed,
            offer: state.incomingOffer!,
            result: state.result,
            message: state.errorMessage ?? 'Couldn\'t finish receiving files.',
            title: 'Couldn\'t finish receiving files',
            onDone: () =>
                ref.read(transfersServiceProvider.notifier).dismissTransferResult(),
          ),
        _ => const EmptyTransfersCard(),
      },
    );
  }
}

Widget _buildTransferResultCard({
  required TransferResultOutcome outcome,
  required TransferIncomingOffer offer,
  required TransferTransferResult? result,
  required String title,
  required String message,
  required VoidCallback onDone,
}) {
  final metrics = outcome == TransferResultOutcome.success && result != null
      ? buildReceiveCompletionMetrics(offer: offer, result: result)
      : null;

  return TransferResultCard(
    outcome: outcome,
    title: title,
    message: message,
    metrics: metrics,
    primaryLabel: 'Done',
    onPrimary: onDone,
  );
}

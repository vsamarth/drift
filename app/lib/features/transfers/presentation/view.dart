import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/controller.dart';
import '../application/service.dart';
import '../application/state.dart';
import 'widgets/completed_card.dart';
import 'widgets/receiving_card.dart';
import 'widgets/offer_card.dart';
import 'widgets/empty_card.dart';

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
        TransferSessionPhase.completed => CompletedCard(
          offer: state.incomingOffer!,
          result: state.result!,
          onDone: () =>
              ref.read(transfersServiceProvider.notifier).dismissTransferResult(),
        ),
        _ => const EmptyTransfersCard(),
      },
    );
  }
}

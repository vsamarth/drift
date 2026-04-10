import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/controller.dart';
import '../application/service.dart';
import '../application/state.dart';
import 'widgets/offer_card.dart';
import 'widgets/empty_card.dart';

class TransfersFeature extends ConsumerWidget {
  const TransfersFeature({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(transfersViewStateProvider);
    final animateReview = ref.watch(transferReviewAnimationProvider);
    return SizedBox.expand(
      child: state.hasIncomingOffer
          ? OfferCard(
              offer: state.incomingOffer!,
              animate: animateReview,
              onAccept: () =>
                  ref.read(transfersServiceProvider.notifier).acceptOffer(),
              onDecline: () =>
                  ref.read(transfersServiceProvider.notifier).declineOffer(),
            )
          : const EmptyTransfersCard(),
    );
  }
}

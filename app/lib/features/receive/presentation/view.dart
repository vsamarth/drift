import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/controller.dart';
import '../../transfers/feature.dart';
import '../../transfers/application/controller.dart';
import 'widgets/idle_card.dart';

class ReceiveFeature extends ConsumerWidget {
  const ReceiveFeature({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receiverState = ref.watch(receiverIdleViewStateProvider);
    final transferState = ref.watch(transfersViewStateProvider);
    final isIdle = transferState.phase == TransferSessionPhase.idle;

    final child = isIdle
        ? Column(
            key: const ValueKey<String>('receive-idle'),
            children: [
              ReceiveIdleCard(state: receiverState),
              const SizedBox(height: 12),
              const Expanded(child: TransfersFeature()),
            ],
          )
        : const SizedBox(
            key: ValueKey<String>('receive-active'),
            width: double.infinity,
            height: double.infinity,
            child: TransfersFeature(),
          );

    return SizedBox.expand(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final fade = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          final slide = Tween<Offset>(
            begin: const Offset(0, 0.03),
            end: Offset.zero,
          ).animate(fade);
          return FadeTransition(
            opacity: fade,
            child: SlideTransition(position: slide, child: child),
          );
        },
        child: child,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/controller.dart';
import '../../settings/presentation/view.dart';
import 'receive_transfer_route_gate.dart';
import 'widgets/idle_card.dart';

class ReceiveFeature extends ConsumerWidget {
  const ReceiveFeature({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receiverState = ref.watch(receiverIdleViewStateProvider);
    return ReceiveTransferRouteGate(
      child: SizedBox.expand(
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
          child: Column(
            key: const ValueKey<String>('receive-idle'),
            children: [
              ReceiveIdleCard(
                state: receiverState,
                onOpenSettings: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsFeature(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

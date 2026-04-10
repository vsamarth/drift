import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/controller.dart';
import 'widgets/idle_card.dart';

class ReceiveFeature extends ConsumerWidget {
  const ReceiveFeature({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(receiverIdleViewStateProvider);
    return ReceiveIdleCard(state: state);
  }
}

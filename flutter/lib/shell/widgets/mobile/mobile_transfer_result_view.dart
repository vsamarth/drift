import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/send/send_providers.dart';
import '../../../features/send/send_state.dart';
import '../transfer_result_card.dart';

class MobileTransferResultView extends ConsumerWidget {
  const MobileTransferResultView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(sendControllerProvider.notifier);
    final result = ref.watch(
      sendStateProvider.select((state) => state.transferResult),
    );

    if (result == null) {
      return const SizedBox.shrink();
    }

    return TransferResultCard(
      fillBody: true,
      outcome: result.outcome,
      title: result.title,
      message: result.message,
      metrics: result.metrics,
      primaryLabel: result.primaryLabel,
      onPrimary: result.primaryLabel == null
          ? null
          : notifier.handleTransferResultPrimaryAction,
    );
  }
}

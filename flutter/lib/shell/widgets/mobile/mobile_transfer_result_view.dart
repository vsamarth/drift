import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/drift_app_state.dart';
import '../../../state/drift_providers.dart';
import '../transfer_result_card.dart';

class MobileTransferResultView extends ConsumerWidget {
  const MobileTransferResultView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(driftAppNotifierProvider.notifier);
    final result = ref.watch(
      driftAppNotifierProvider.select((state) => state.transferResult),
    );

    if (result == null) {
      return const SizedBox.shrink();
    }

    return TransferResultCard(
      fillBody: true,
      tone: switch (result.tone) {
        TransferResultToneData.success => TransferResultTone.success,
        TransferResultToneData.error => TransferResultTone.error,
      },
      title: result.title,
      message: result.message,
      metrics: result.metrics,
      primaryLabel: result.primaryLabel,
      onPrimary: result.primaryLabel == null ? null : notifier.resetShell,
    );
  }
}

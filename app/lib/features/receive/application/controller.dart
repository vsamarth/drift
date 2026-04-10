import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'service.dart';
import 'state.dart';

part 'controller.g.dart';

@riverpod
ReceiverIdleViewState receiverIdleViewState(Ref ref) {
  final service = ref.watch(receiverServiceProvider);
  final snapshot = service.snapshot;
  final pairingCode = service.pairingCode;

  final badge = switch (snapshot.lifecycle) {
    ReceiverLifecycle.starting => const ReceiverBadgeState.registering(),
    ReceiverLifecycle.ready => pairingCode.isAvailable
        ? const ReceiverBadgeState.ready()
        : const ReceiverBadgeState.unavailable(),
    ReceiverLifecycle.stopped => const ReceiverBadgeState.unavailable(),
    ReceiverLifecycle.failed => const ReceiverBadgeState.unavailable(),
  };

  final code =
      pairingCode.isAvailable ? pairingCode.formattedCode : '......';

  return ReceiverIdleViewState(
    deviceName: 'Drift',
    badge: badge,
    status: badge.label,
    code: code,
    clipboardCode: pairingCode.clipboardCode,
    lifecycle: snapshot.lifecycle,
  );
}

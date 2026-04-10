import 'package:flutter/material.dart';
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
    ReceiverLifecycle.starting => const ReceiverBadgeState(
        phase: ReceiverBadgePhase.registering,
        label: 'Registering',
        color: Color(0xFFD4A824),
      ),
    ReceiverLifecycle.ready => pairingCode.isAvailable
        ? const ReceiverBadgeState(
            phase: ReceiverBadgePhase.ready,
            label: 'Ready',
            color: Color(0xFF49B36C),
          )
        : const ReceiverBadgeState(
            phase: ReceiverBadgePhase.unavailable,
            label: 'Unavailable',
            color: Color(0xFF8A8A8A),
          ),
    ReceiverLifecycle.stopped => const ReceiverBadgeState(
        phase: ReceiverBadgePhase.unavailable,
        label: 'Unavailable',
        color: Color(0xFF8A8A8A),
      ),
    ReceiverLifecycle.failed => const ReceiverBadgeState(
        phase: ReceiverBadgePhase.unavailable,
        label: 'Unavailable',
        color: Color(0xFF8A8A8A),
      ),
  };

  final code =
      pairingCode.isAvailable ? pairingCode.formattedCode : '......';

  return ReceiverIdleViewState(
    title: 'Receiver',
    badge: badge,
    status: badge.label,
    code: code,
    lifecycle: snapshot.lifecycle,
  );
}

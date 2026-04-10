import 'package:flutter/material.dart';

enum ReceiverLifecycle { starting, ready, stopped, failed }

enum ReceiverBadgePhase { unavailable, registering, ready }

@immutable
class ReceiverSnapshot {
  const ReceiverSnapshot({
    required this.lifecycle,
    required this.discoverableRequested,
    required this.advertisingActive,
    required this.hasRegistration,
    required this.hasPendingOffer,
  });

  final ReceiverLifecycle lifecycle;
  final bool discoverableRequested;
  final bool advertisingActive;
  final bool hasRegistration;
  final bool hasPendingOffer;
}

@immutable
class PairingCodeState {
  const PairingCodeState.unavailable()
      : code = null,
        expiresAt = null;

  const PairingCodeState.active({
    required this.code,
    this.expiresAt,
  });

  final String? code;
  final String? expiresAt;

  bool get isAvailable => code != null && code!.trim().isNotEmpty;

  String get formattedCode {
    final value = (code ?? '').replaceAll(' ', '').trim().toUpperCase();
    if (value.length != 6) {
      return value;
    }
    return '${value.substring(0, 3)} ${value.substring(3)}';
  }
}

@immutable
class NearbyReceiver {
  const NearbyReceiver({
    required this.fullname,
    required this.label,
    required this.code,
    required this.ticket,
  });

  final String fullname;
  final String label;
  final String code;
  final String ticket;
}

@immutable
class ReceiverBadgeState {
  const ReceiverBadgeState({
    required this.phase,
    required this.label,
    required this.color,
  });

  final ReceiverBadgePhase phase;
  final String label;
  final Color color;
}

@immutable
class ReceiverIdleViewState {
  const ReceiverIdleViewState({
    required this.title,
    required this.badge,
    required this.status,
    required this.code,
    required this.lifecycle,
  });

  final String title;
  final ReceiverBadgeState badge;
  final String status;
  final String code;
  final ReceiverLifecycle lifecycle;
}

@immutable
class ReceiverServiceState {
  const ReceiverServiceState({
    required this.snapshot,
    required this.pairingCode,
  });

  const ReceiverServiceState.ready()
      : snapshot = const ReceiverSnapshot(
          lifecycle: ReceiverLifecycle.ready,
          discoverableRequested: false,
          advertisingActive: false,
          hasRegistration: true,
          hasPendingOffer: false,
        ),
        pairingCode = const PairingCodeState.active(
          code: 'ABC123',
          expiresAt: '2099-01-01T00:00:00Z',
        );

  const ReceiverServiceState.unavailable()
      : snapshot = const ReceiverSnapshot(
          lifecycle: ReceiverLifecycle.ready,
          discoverableRequested: false,
          advertisingActive: false,
          hasRegistration: false,
          hasPendingOffer: false,
        ),
        pairingCode = const PairingCodeState.unavailable();

  const ReceiverServiceState.registering()
      : snapshot = const ReceiverSnapshot(
          lifecycle: ReceiverLifecycle.starting,
          discoverableRequested: false,
          advertisingActive: false,
          hasRegistration: false,
          hasPendingOffer: false,
        ),
        pairingCode = const PairingCodeState.unavailable();

  final ReceiverSnapshot snapshot;
  final PairingCodeState pairingCode;
}

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
  const PairingCodeState.unavailable() : code = null, expiresAt = null;

  const PairingCodeState.active({required this.code, this.expiresAt});

  final String? code;
  final String? expiresAt;

  bool get isAvailable => code != null && code!.trim().isNotEmpty;

  String get normalizedCode {
    return (code ?? '').replaceAll(' ', '').trim().toUpperCase();
  }

  String get clipboardCode => normalizedCode;

  String get formattedCode {
    final value = normalizedCode;
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
  const ReceiverBadgeState._({
    required this.phase,
    required this.label,
    required this.color,
  });

  const ReceiverBadgeState.unavailable()
    : this._(
        phase: ReceiverBadgePhase.unavailable,
        label: 'Unavailable',
        color: const Color(0xFF8A8A8A),
      );

  const ReceiverBadgeState.registering()
    : this._(
        phase: ReceiverBadgePhase.registering,
        label: 'Registering',
        color: const Color(0xFFD4A824),
      );

  const ReceiverBadgeState.ready()
    : this._(
        phase: ReceiverBadgePhase.ready,
        label: 'Ready',
        color: const Color(0xFF49B36C),
      );

  final ReceiverBadgePhase phase;
  final String label;
  final Color color;
}

@immutable
class ReceiverIdleViewState {
  const ReceiverIdleViewState({
    required this.deviceName,
    required this.badge,
    required this.status,
    required this.code,
    required this.clipboardCode,
    required this.lifecycle,
  });

  final String deviceName;
  final ReceiverBadgeState badge;
  final String status;
  final String code;
  final String clipboardCode;
  final ReceiverLifecycle lifecycle;
}

@immutable
class ReceiverServiceState {
  const ReceiverServiceState({
    required this.snapshot,
    required this.pairingCode,
  });

  factory ReceiverServiceState.ready({
    required String code,
    String? expiresAt,
  }) {
    return ReceiverServiceState(
      snapshot: const ReceiverSnapshot(
        lifecycle: ReceiverLifecycle.ready,
        discoverableRequested: false,
        advertisingActive: false,
        hasRegistration: true,
        hasPendingOffer: false,
      ),
      pairingCode: PairingCodeState.active(code: code, expiresAt: expiresAt),
    );
  }

  const ReceiverServiceState.unavailable()
    : snapshot = const ReceiverSnapshot(
        lifecycle: ReceiverLifecycle.stopped,
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

  const ReceiverServiceState.stopped()
    : snapshot = const ReceiverSnapshot(
        lifecycle: ReceiverLifecycle.stopped,
        discoverableRequested: false,
        advertisingActive: false,
        hasRegistration: false,
        hasPendingOffer: false,
      ),
      pairingCode = const PairingCodeState.unavailable();

  const ReceiverServiceState.failed()
    : snapshot = const ReceiverSnapshot(
        lifecycle: ReceiverLifecycle.failed,
        discoverableRequested: false,
        advertisingActive: false,
        hasRegistration: false,
        hasPendingOffer: false,
      ),
      pairingCode = const PairingCodeState.unavailable();

  final ReceiverSnapshot snapshot;
  final PairingCodeState pairingCode;

  ReceiverServiceState copyWith({
    ReceiverSnapshot? snapshot,
    PairingCodeState? pairingCode,
  }) {
    return ReceiverServiceState(
      snapshot: snapshot ?? this.snapshot,
      pairingCode: pairingCode ?? this.pairingCode,
    );
  }
}

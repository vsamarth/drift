import 'package:flutter/material.dart';

import '../platform/storage_access_source.dart';
import '../src/rust/api/receiver.dart' as rust_receiver;
import 'app_identity.dart';

enum ReceiverBadgePhase { unavailable, registering, ready }

class ReceiverBadgeState {
  const ReceiverBadgeState({
    required this.code,
    required this.status,
    required this.phase,
    this.expiresAt,
  });

  const ReceiverBadgeState.registering()
    : code = '......',
      status = 'Registering',
      phase = ReceiverBadgePhase.registering,
      expiresAt = null;

  const ReceiverBadgeState.unavailable()
    : code = '......',
      status = 'Unavailable',
      phase = ReceiverBadgePhase.unavailable,
      expiresAt = null;

  final String code;
  final String status;
  final ReceiverBadgePhase phase;
  final String? expiresAt;

  Color get statusColor => switch (phase) {
    ReceiverBadgePhase.unavailable => const Color(0xFF8A8A8A),
    ReceiverBadgePhase.registering => const Color(0xFFD4A824),
    ReceiverBadgePhase.ready => const Color(0xFF49B36C),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReceiverBadgeState &&
          runtimeType == other.runtimeType &&
          code == other.code &&
          status == other.status &&
          phase == other.phase &&
          expiresAt == other.expiresAt;

  @override
  int get hashCode => Object.hash(code, status, phase, expiresAt);
}

abstract class ReceiverServiceSource {
  Stream<ReceiverBadgeState> watchBadge(DriftAppIdentity identity);

  Stream<rust_receiver.ReceiverTransferEvent> watchIncomingTransfers(
    DriftAppIdentity identity,
  );

  Future<void> setDiscoverable({required bool enabled});

  Future<void> respondToOffer({required bool accept});
}

class LocalReceiverServiceSource implements ReceiverServiceSource {
  const LocalReceiverServiceSource(this._storageAccessSource);

  final StorageAccessSource _storageAccessSource;

  @override
  Stream<ReceiverBadgeState> watchBadge(DriftAppIdentity identity) {
    return Stream<void>.fromFuture(
      _storageAccessSource.restorePersistedAccess(path: identity.downloadRoot),
    ).asyncExpand(
      (_) => rust_receiver
          .watchReceiverPairing(
            serverUrl: identity.serverUrl,
            downloadRoot: identity.downloadRoot,
            deviceName: identity.deviceName,
            deviceType: identity.deviceType,
          )
          .map(_mapPairingState),
    );
  }

  @override
  Stream<rust_receiver.ReceiverTransferEvent> watchIncomingTransfers(
    DriftAppIdentity identity,
  ) {
    return Stream<void>.fromFuture(
      _storageAccessSource.restorePersistedAccess(path: identity.downloadRoot),
    ).asyncExpand(
      (_) => rust_receiver.startReceiverTransferListener(
        serverUrl: identity.serverUrl,
        downloadRoot: identity.downloadRoot,
        deviceName: identity.deviceName,
        deviceType: identity.deviceType,
      ),
    );
  }

  @override
  Future<void> setDiscoverable({required bool enabled}) {
    return rust_receiver.setReceiverDiscoverable(enabled: enabled);
  }

  @override
  Future<void> respondToOffer({required bool accept}) {
    return rust_receiver.respondToReceiverOffer(accept: accept);
  }
}

ReceiverBadgeState _mapPairingState(rust_receiver.ReceiverPairingState state) {
  final code = (state.code ?? '').trim().toUpperCase();
  if (code.isEmpty) {
    return const ReceiverBadgeState.unavailable();
  }
  return ReceiverBadgeState(
    code: code,
    status: 'Ready',
    phase: ReceiverBadgePhase.ready,
    expiresAt: state.expiresAt,
  );
}

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../src/rust/api/receiver.dart' as rust_receiver;
import 'app_identity.dart';

@immutable
class ReceiverBadgeState {
  const ReceiverBadgeState({
    required this.code,
    required this.status,
    this.expiresAt,
  });

  const ReceiverBadgeState.registering()
    : code = '......',
      status = 'Registering',
      expiresAt = null;

  const ReceiverBadgeState.unavailable()
    : code = '......',
      status = 'Unavailable',
      expiresAt = null;

  final String code;
  final String status;
  final String? expiresAt;
}

class ReceiverServiceController extends ChangeNotifier {
  ReceiverServiceController({
    String? deviceName,
    String? deviceType,
    String? downloadRoot,
  }) : _identity = buildDefaultDriftAppIdentity(
         deviceName: deviceName,
         deviceType: deviceType,
         downloadRoot: downloadRoot,
       ) {
    unawaited(_start());
  }

  final DriftAppIdentity _identity;
  StreamSubscription<rust_receiver.ReceiverPairingState>? _pairingSubscription;
  ReceiverBadgeState _badgeState = const ReceiverBadgeState.registering();

  DriftAppIdentity get identity => _identity;
  ReceiverBadgeState get badgeState => _badgeState;

  Future<void> _start() async {
    await _pairingSubscription?.cancel();
    _pairingSubscription = rust_receiver
        .watchReceiverPairing(
          downloadRoot: _identity.downloadRoot,
          deviceName: _identity.deviceName,
          deviceType: _identity.deviceType,
        )
        .listen(
          _applyPairingState,
          onError: (Object error, StackTrace stackTrace) {
            debugPrint('watchReceiverPairing failed: $error');
            debugPrintStack(stackTrace: stackTrace);
            _setBadgeState(const ReceiverBadgeState.unavailable());
          },
        );
  }

  void _applyPairingState(rust_receiver.ReceiverPairingState state) {
    final code = (state.code ?? '').trim().toUpperCase();
    if (code.isEmpty) {
      _setBadgeState(const ReceiverBadgeState.unavailable());
      return;
    }

    _setBadgeState(
      ReceiverBadgeState(
        code: code,
        status: 'Ready',
        expiresAt: state.expiresAt,
      ),
    );
  }

  void _setBadgeState(ReceiverBadgeState next) {
    final current = _badgeState;
    if (current.code == next.code &&
        current.status == next.status &&
        current.expiresAt == next.expiresAt) {
      return;
    }
    _badgeState = next;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_pairingSubscription?.cancel());
    _pairingSubscription = null;
    super.dispose();
  }
}

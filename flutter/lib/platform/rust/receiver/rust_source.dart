import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../features/receive/application/state.dart';
import '../../../src/rust/api/lan.dart' as rust_lan;
import '../../../src/rust/api/receiver.dart' as rust_receiver;
import 'mapper.dart';
import 'source.dart';

typedef ReceiverPairingStreamFactory =
    Stream<rust_receiver.ReceiverPairingState> Function({
      String? serverUrl,
      required String downloadRoot,
      required String deviceName,
      required String deviceType,
    });

typedef ReceiverTransferStreamFactory =
    Stream<rust_receiver.ReceiverTransferEvent> Function({
      String? serverUrl,
      required String downloadRoot,
      required String deviceName,
      required String deviceType,
    });

class RustReceiverServiceSource implements ReceiverServiceSource {
  RustReceiverServiceSource({
    required this.deviceName,
    required this.downloadRoot,
    this.serverUrl,
    ReceiverPairingStreamFactory? pairingStreamFactory,
    ReceiverTransferStreamFactory? transferStreamFactory,
  }) : _pairingStreamFactory =
           pairingStreamFactory ?? rust_receiver.watchReceiverPairing,
       _transferStreamFactory =
           transferStreamFactory ?? rust_receiver.startReceiverTransferListener;

  String deviceName;
  String downloadRoot;
  String? serverUrl;

  final ReceiverPairingStreamFactory _pairingStreamFactory;
  final ReceiverTransferStreamFactory _transferStreamFactory;
  final StreamController<ReceiverServiceState> _stateController =
      StreamController<ReceiverServiceState>.broadcast(sync: true);
  final StreamController<rust_receiver.ReceiverTransferEvent>
  _transferController =
      StreamController<rust_receiver.ReceiverTransferEvent>.broadcast(
        sync: true,
      );

  StreamSubscription<rust_receiver.ReceiverPairingState>? _pairingSubscription;
  StreamSubscription<rust_receiver.ReceiverTransferEvent>?
  _transferSubscription;
  int _configGeneration = 0;
  ReceiverServiceState _currentState = const ReceiverServiceState.registering();

  @override
  ReceiverServiceState get currentState => _currentState;

  @override
  Stream<ReceiverServiceState> watchState() {
    _ensurePairingSubscription();
    return _stateController.stream;
  }

  @override
  Stream<rust_receiver.ReceiverTransferEvent> watchIncomingTransfers() {
    _ensureTransferSubscription();
    return _transferController.stream;
  }

  @override
  Future<void> setup({String? serverUrl}) async {
    debugPrint(
      '[receiver] setup request '
      'device="$deviceName" '
      'downloadRoot="$downloadRoot" '
      'serverUrl="${serverUrl ?? _resolvedServerUrl}"',
    );
    await rust_receiver.registerReceiver(
      serverUrl: serverUrl ?? _resolvedServerUrl,
      deviceName: deviceName,
    );
    debugPrint('[receiver] setup complete');
  }

  @override
  Future<void> ensureRegistered({String? serverUrl}) async {
    debugPrint(
      '[receiver] ensureRegistered request '
      'device="$deviceName" '
      'serverUrl="${serverUrl ?? _resolvedServerUrl}"',
    );
    await rust_receiver.ensureReceiverRegistration(
      serverUrl: serverUrl ?? _resolvedServerUrl,
      deviceName: deviceName,
    );
    debugPrint('[receiver] ensureRegistered complete');
  }

  @override
  Future<void> updateIdentity({
    required String deviceName,
    required String downloadRoot,
    String? serverUrl,
  }) async {
    final previousDeviceName = this.deviceName;
    final previousDownloadRoot = this.downloadRoot;
    final previousServerUrl = this.serverUrl;
    this.deviceName = deviceName;
    this.downloadRoot = downloadRoot;
    this.serverUrl = serverUrl;
    debugPrint(
      '[receiver] updateIdentity '
      'from device="$previousDeviceName" downloadRoot="$previousDownloadRoot" '
      'serverUrl="${previousServerUrl ?? _resolvedServerUrl}" '
      'to device="$deviceName" downloadRoot="$downloadRoot" '
      'serverUrl="${serverUrl ?? _resolvedServerUrl}"',
    );
    final generation = ++_configGeneration;

    if (_pairingSubscription != null) {
      debugPrint('[receiver] restarting pairing stream');
      _restartPairingSubscription(generation: generation);
    }
    if (_transferSubscription != null) {
      debugPrint('[receiver] restarting transfer stream');
      _restartTransferSubscription(generation: generation);
    }
  }

  @override
  Future<void> setDiscoverable({required bool enabled}) {
    debugPrint('[receiver] discoverable ${enabled ? 'enabled' : 'disabled'}');
    return rust_receiver.setReceiverDiscoverable(enabled: enabled);
  }

  @override
  Future<void> respondToOffer({required bool accept}) {
    return rust_receiver.respondToReceiverOffer(accept: accept);
  }

  @override
  Future<void> cancelTransfer() {
    return rust_receiver.cancelReceiverTransfer();
  }

  @override
  Future<List<NearbyReceiver>> scanNearby({required Duration timeout}) async {
    final peers = await rust_lan.scanNearbyReceivers(
      timeoutSecs: BigInt.from(timeout.inSeconds.clamp(1, 60).toInt()),
    );
    return peers
        .map(
          (peer) => NearbyReceiver(
            fullname: peer.fullname,
            label: peer.label,
            deviceType: peer.deviceType,
            code: peer.code,
            ticket: peer.ticket,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> shutdown() async {
    debugPrint('[receiver] shutdown');
    unawaited(_pairingSubscription?.cancel());
    unawaited(_transferSubscription?.cancel());
    _pairingSubscription = null;
    _transferSubscription = null;
    await rust_receiver.setReceiverDiscoverable(enabled: false);
  }

  void _restartPairingSubscription({required int generation}) {
    final oldSubscription = _pairingSubscription;
    debugPrint('[receiver] pairing stream generation=$generation start');
    _pairingSubscription = null;
    _currentState = const ReceiverServiceState.registering();
    if (!_stateController.isClosed) {
      _stateController.add(_currentState);
    }
    final stream = _pairingStreamFactory(
      serverUrl: _resolvedServerUrl,
      downloadRoot: downloadRoot,
      deviceName: deviceName,
      deviceType: _deviceType,
    );
    _pairingSubscription = stream.listen(
      (pairing) {
        if (generation != _configGeneration) {
          debugPrint(
            '[receiver] pairing stream generation=$generation ignored stale event',
          );
          return;
        }
        final nextState = mapReceiverPairingState(pairing);
        _currentState = nextState;
        if (!_stateController.isClosed) {
          _stateController.add(nextState);
        }
      },
      onError: (_) {
        if (generation != _configGeneration) {
          return;
        }
        debugPrint('[receiver] pairing stream generation=$generation error');
        _currentState = const ReceiverServiceState.unavailable();
        if (!_stateController.isClosed) {
          _stateController.add(_currentState);
        }
      },
    );
    unawaited(oldSubscription?.cancel());
  }

  void _restartTransferSubscription({required int generation}) {
    final oldSubscription = _transferSubscription;
    debugPrint('[receiver] transfer stream generation=$generation start');
    _transferSubscription = null;
    final stream = _transferStreamFactory(
      serverUrl: _resolvedServerUrl,
      downloadRoot: downloadRoot,
      deviceName: deviceName,
      deviceType: _deviceType,
    );
    _transferSubscription = stream.listen(
      (event) {
        if (generation != _configGeneration) {
          debugPrint(
            '[receiver] transfer stream generation=$generation ignored stale event',
          );
          return;
        }
        if (!_transferController.isClosed) {
          _transferController.add(event);
        }
      },
      onError: (_) {
        debugPrint('[receiver] transfer stream generation=$generation error');
      },
    );
    unawaited(oldSubscription?.cancel());
  }

  void _ensurePairingSubscription() {
    if (_pairingSubscription != null) {
      return;
    }
    _restartPairingSubscription(generation: ++_configGeneration);
  }

  void _ensureTransferSubscription() {
    if (_transferSubscription != null) {
      return;
    }
    _restartTransferSubscription(generation: _configGeneration);
  }

  String get _resolvedServerUrl => serverUrl ?? 'http://127.0.0.1:8787';

  static String get _deviceType => switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => 'phone',
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux => 'laptop',
    TargetPlatform.fuchsia => 'laptop',
  };
}

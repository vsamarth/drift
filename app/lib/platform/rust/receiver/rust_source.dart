import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../features/receive/application/state.dart';
import '../../../src/rust/api/lan.dart' as rust_lan;
import '../../../src/rust/api/receiver.dart' as rust_receiver;
import 'mapper.dart';
import 'source.dart';

class RustReceiverServiceSource implements ReceiverServiceSource {
  const RustReceiverServiceSource();

  static const String _deviceName = 'Drift';

  @override
  ReceiverServiceState get currentState => const ReceiverServiceState.registering();

  @override
  Stream<ReceiverServiceState> watchState() async* {
    yield const ReceiverServiceState.registering();

    try {
      await rust_receiver.ensureReceiverRegistration(
        serverUrl: _serverUrl,
        deviceName: _deviceName,
      );
      await rust_receiver.setReceiverDiscoverable(enabled: true);

      await for (final pairing in rust_receiver.watchReceiverPairing(
        serverUrl: _serverUrl,
        downloadRoot: _downloadRoot,
        deviceName: _deviceName,
        deviceType: _deviceType,
      )) {
        yield mapReceiverPairingState(pairing);
      }
    } catch (_) {
      yield const ReceiverServiceState.unavailable();
    }
  }

  @override
  Future<void> setup({String? serverUrl}) async {
    await rust_receiver.registerReceiver(
      serverUrl: serverUrl ?? _serverUrl,
      deviceName: _deviceName,
    );
  }

  @override
  Future<void> ensureRegistered({String? serverUrl}) async {
    await rust_receiver.ensureReceiverRegistration(
      serverUrl: serverUrl ?? _serverUrl,
      deviceName: _deviceName,
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
            code: peer.code,
            ticket: peer.ticket,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> shutdown() async {
    await rust_receiver.setReceiverDiscoverable(enabled: false);
  }

  static String get _downloadRoot =>
      '${Directory.systemTemp.path}${Platform.pathSeparator}Drift';

  static String get _deviceType =>
      switch (defaultTargetPlatform) {
        TargetPlatform.android || TargetPlatform.iOS => 'phone',
        TargetPlatform.macOS ||
        TargetPlatform.windows ||
        TargetPlatform.linux => 'laptop',
        TargetPlatform.fuchsia => 'laptop',
      };

  static String? get _serverUrl => 'https://drift.samarthv.com';
}

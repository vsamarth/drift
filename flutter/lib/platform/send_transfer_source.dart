import 'package:flutter/foundation.dart';

import '../src/rust/api/sender.dart' as rust_sender;

class SendTransferRequestData {
  const SendTransferRequestData({
    required this.code,
    required this.paths,
    required this.deviceName,
    required this.deviceType,
    this.serverUrl,
    this.ticket,
    this.lanDestinationLabel,
  });

  final String code;
  final List<String> paths;
  final String deviceName;
  /// `"phone"` or `"laptop"`.
  final String deviceType;
  final String? serverUrl;

  /// When set, Rust uses LAN ticket path; [code] is only for UI / labels.
  final String? ticket;

  /// Progress label when sending via [ticket].
  final String? lanDestinationLabel;
}

enum SendTransferUpdatePhase {
  connecting,
  waitingForDecision,
  sending,
  completed,
  failed,
}

class SendTransferUpdate {
  const SendTransferUpdate({
    required this.phase,
    required this.destinationLabel,
    required this.statusMessage,
    required this.itemCount,
    required this.totalSize,
    required this.bytesSent,
    required this.totalBytes,
    this.remoteDeviceType,
    this.errorMessage,
  });

  final SendTransferUpdatePhase phase;
  final String destinationLabel;
  final String statusMessage;
  final int itemCount;
  final String totalSize;
  final int bytesSent;
  final int totalBytes;
  /// `"phone"` or `"laptop"`, when known yet.
  final String? remoteDeviceType;
  final String? errorMessage;
}

abstract class SendTransferSource {
  Stream<SendTransferUpdate> startTransfer(SendTransferRequestData request);
}

class LocalSendTransferSource implements SendTransferSource {
  const LocalSendTransferSource();

  @override
  Stream<SendTransferUpdate> startTransfer(SendTransferRequestData request) {
    debugPrint(
      '[drift/send] startTransfer code=${request.code} '
      'ticket=${request.ticket == null ? 'no' : 'yes'} '
      'files=${request.paths.length} server=${request.serverUrl ?? '(default)'}',
    );
    return rust_sender
        .startSendTransfer(
          request: rust_sender.SendTransferRequest(
            code: request.code,
            paths: request.paths,
            serverUrl: request.serverUrl,
            deviceName: request.deviceName,
            deviceType: request.deviceType,
            ticket: request.ticket,
            lanDestinationLabel: request.lanDestinationLabel,
          ),
        )
        .map((event) {
          final mapped = _mapEvent(event);
          debugPrint(
            '[drift/send] update phase=${mapped.phase.name} '
            'destination=${mapped.destinationLabel} '
            'items=${mapped.itemCount} total=${mapped.totalSize} '
            'payload=${mapped.bytesSent}/${mapped.totalBytes} B'
            '${mapped.errorMessage == null ? '' : ' error=${mapped.errorMessage}'}',
          );
          return mapped;
        });
  }

  static SendTransferUpdate _mapEvent(rust_sender.SendTransferEvent event) {
    return SendTransferUpdate(
      phase: switch (event.phase) {
        rust_sender.SendTransferPhase.connecting =>
          SendTransferUpdatePhase.connecting,
        rust_sender.SendTransferPhase.waitingForDecision =>
          SendTransferUpdatePhase.waitingForDecision,
        rust_sender.SendTransferPhase.sending =>
          SendTransferUpdatePhase.sending,
        rust_sender.SendTransferPhase.completed =>
          SendTransferUpdatePhase.completed,
        rust_sender.SendTransferPhase.failed => SendTransferUpdatePhase.failed,
      },
      destinationLabel: event.destinationLabel,
      statusMessage: event.statusMessage,
      itemCount: event.itemCount.toInt(),
      totalSize: _formatBytes(event.totalSize.toInt()),
      bytesSent: _asDartInt(event.bytesSent),
      totalBytes: _asDartInt(event.totalSize),
      remoteDeviceType: event.remoteDeviceType,
      errorMessage: event.errorMessage,
    );
  }

  static int _asDartInt(BigInt v) {
    if (v.bitLength > 63) {
      return 0x7fffffffffffffff;
    }
    return v.toInt();
  }

  static String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unitIndex = 0;

    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex += 1;
    }

    final decimals = value >= 10 || unitIndex == 0 ? 0 : 1;
    final formatted = value.toStringAsFixed(decimals);
    return '$formatted ${units[unitIndex]}';
  }
}

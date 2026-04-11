import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/rust/api/error.dart' as rust_error;
import '../src/rust/api/sender.dart' as rust_sender;

final sendTransferSourceProvider = Provider<SendTransferSource>((_) {
  return const LocalSendTransferSource();
});

abstract class SendTransferSource {
  Stream<SendTransferUpdate> startTransfer(SendTransferRequestData request);

  Future<void> cancelTransfer();
}

@immutable
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
  final String deviceType;
  final String? serverUrl;
  final String? ticket;
  final String? lanDestinationLabel;
}

enum SendTransferUpdatePhase {
  connecting,
  waitingForDecision,
  accepted,
  declined,
  sending,
  completed,
  cancelled,
  failed,
}

@immutable
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
    this.error,
  });

  const SendTransferUpdate.completed({
    required String destinationLabel,
    required String statusMessage,
    required BigInt itemCount,
    required BigInt totalSize,
    required BigInt bytesSent,
    String? remoteDeviceType,
  }) : this(
         phase: SendTransferUpdatePhase.completed,
         destinationLabel: destinationLabel,
         statusMessage: statusMessage,
         itemCount: itemCount,
         totalSize: totalSize,
         bytesSent: bytesSent,
         totalBytes: totalSize,
         remoteDeviceType: remoteDeviceType,
       );

  const SendTransferUpdate.failed({
    required String destinationLabel,
    required String statusMessage,
    required BigInt itemCount,
    required BigInt totalSize,
    required BigInt bytesSent,
    required BigInt totalBytes,
    SendTransferErrorData? error,
    String? remoteDeviceType,
  }) : this(
         phase: SendTransferUpdatePhase.failed,
         destinationLabel: destinationLabel,
         statusMessage: statusMessage,
         itemCount: itemCount,
         totalSize: totalSize,
         bytesSent: bytesSent,
         totalBytes: totalBytes,
         remoteDeviceType: remoteDeviceType,
         error: error,
       );

  const SendTransferUpdate.cancelled({
    required String destinationLabel,
    required String statusMessage,
    required BigInt itemCount,
    required BigInt totalSize,
    required BigInt bytesSent,
    required BigInt totalBytes,
    SendTransferErrorData? error,
    String? remoteDeviceType,
  }) : this(
         phase: SendTransferUpdatePhase.cancelled,
         destinationLabel: destinationLabel,
         statusMessage: statusMessage,
         itemCount: itemCount,
         totalSize: totalSize,
         bytesSent: bytesSent,
         totalBytes: totalBytes,
         remoteDeviceType: remoteDeviceType,
         error: error,
       );

  final SendTransferUpdatePhase phase;
  final String destinationLabel;
  final String statusMessage;
  final BigInt itemCount;
  final BigInt totalSize;
  final BigInt bytesSent;
  final BigInt totalBytes;
  final String? remoteDeviceType;
  final SendTransferErrorData? error;
}

@immutable
class SendTransferErrorData {
  const SendTransferErrorData({
    required this.kind,
    required this.title,
    required this.message,
    required this.retryable,
    this.recovery,
  });

  final SendTransferErrorKind kind;
  final String title;
  final String message;
  final bool retryable;
  final String? recovery;
}

enum SendTransferErrorKind {
  invalidInput,
  pairingUnavailable,
  peerDeclined,
  networkUnavailable,
  connectionLost,
  permissionDenied,
  fileConflict,
  protocolIncompatible,
  cancelled,
  internal,
  other,
}

class LocalSendTransferSource implements SendTransferSource {
  const LocalSendTransferSource({
    this.startTransferFn = rust_sender.startSendTransfer,
    this.cancelTransferFn = rust_sender.cancelActiveSendTransfer,
  });

  final Stream<rust_sender.SendTransferEvent> Function({
    required rust_sender.SendTransferRequest request,
  })
  startTransferFn;
  final Future<void> Function() cancelTransferFn;

  @override
  Stream<SendTransferUpdate> startTransfer(SendTransferRequestData request) {
    return startTransferFn(
      request: rust_sender.SendTransferRequest(
        code: request.code,
        paths: request.paths,
        serverUrl: request.serverUrl,
        deviceName: request.deviceName,
        deviceType: request.deviceType,
        ticket: request.ticket,
        lanDestinationLabel: request.lanDestinationLabel,
      ),
    ).map(_mapEvent);
  }

  @override
  Future<void> cancelTransfer() {
    return cancelTransferFn();
  }

  static SendTransferUpdate _mapEvent(rust_sender.SendTransferEvent event) {
    final totalSize = event.totalSize;
    return SendTransferUpdate(
      phase: switch (event.phase) {
        rust_sender.SendTransferPhase.connecting =>
          SendTransferUpdatePhase.connecting,
        rust_sender.SendTransferPhase.waitingForDecision =>
          SendTransferUpdatePhase.waitingForDecision,
        rust_sender.SendTransferPhase.accepted =>
          SendTransferUpdatePhase.accepted,
        rust_sender.SendTransferPhase.declined =>
          SendTransferUpdatePhase.declined,
        rust_sender.SendTransferPhase.sending =>
          SendTransferUpdatePhase.sending,
        rust_sender.SendTransferPhase.completed =>
          SendTransferUpdatePhase.completed,
        rust_sender.SendTransferPhase.cancelled =>
          SendTransferUpdatePhase.cancelled,
        rust_sender.SendTransferPhase.failed => SendTransferUpdatePhase.failed,
      },
      destinationLabel: event.destinationLabel,
      statusMessage: event.statusMessage,
      itemCount: event.itemCount,
      totalSize: totalSize,
      bytesSent: event.bytesSent,
      totalBytes: totalSize,
      remoteDeviceType: event.remoteDeviceType,
      error: _mapError(event.error),
    );
  }

  static SendTransferErrorData? _mapError(
    rust_error.UserFacingErrorData? error,
  ) {
    if (error == null) {
      return null;
    }

    return SendTransferErrorData(
      kind: switch (error.kind) {
        rust_error.UserFacingErrorKindData.invalidInput =>
          SendTransferErrorKind.invalidInput,
        rust_error.UserFacingErrorKindData.pairingUnavailable =>
          SendTransferErrorKind.pairingUnavailable,
        rust_error.UserFacingErrorKindData.peerDeclined =>
          SendTransferErrorKind.peerDeclined,
        rust_error.UserFacingErrorKindData.networkUnavailable =>
          SendTransferErrorKind.networkUnavailable,
        rust_error.UserFacingErrorKindData.connectionLost =>
          SendTransferErrorKind.connectionLost,
        rust_error.UserFacingErrorKindData.permissionDenied =>
          SendTransferErrorKind.permissionDenied,
        rust_error.UserFacingErrorKindData.fileConflict =>
          SendTransferErrorKind.fileConflict,
        rust_error.UserFacingErrorKindData.protocolIncompatible =>
          SendTransferErrorKind.protocolIncompatible,
        rust_error.UserFacingErrorKindData.cancelled =>
          SendTransferErrorKind.cancelled,
        rust_error.UserFacingErrorKindData.internal =>
          SendTransferErrorKind.internal,
        rust_error.UserFacingErrorKindData.other => SendTransferErrorKind.other,
      },
      title: error.title,
      message: error.message,
      retryable: error.retryable,
      recovery: error.recovery,
    );
  }
}

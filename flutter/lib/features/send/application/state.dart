import 'package:flutter/foundation.dart';

import 'model.dart';
import 'transfer_state.dart';

@immutable
class SendDestinationState {
  const SendDestinationState.none()
      : mode = SendDestinationMode.none,
        code = null,
        ticket = null,
        lanDestinationLabel = null;

  const SendDestinationState.code(this.code)
      : mode = SendDestinationMode.code,
        ticket = null,
        lanDestinationLabel = null;

  const SendDestinationState.nearby({
    required this.ticket,
    required this.lanDestinationLabel,
  })  : mode = SendDestinationMode.nearby,
        code = null;

  final SendDestinationMode mode;
  final String? code;
  final String? ticket;
  final String? lanDestinationLabel;
}

@immutable
sealed class SendState {
  const SendState();
}

class SendStateIdle extends SendState {
  const SendStateIdle();
}

class SendStateDrafting extends SendState {
  const SendStateDrafting({
    required this.items,
    this.destination = const SendDestinationState.none(),
    this.resolvedDirectorySizes = const {},
  });

  final List<SendDraftItem> items;
  final SendDestinationState destination;
  final Map<String, BigInt> resolvedDirectorySizes;

  SendStateDrafting copyWith({
    List<SendDraftItem>? items,
    SendDestinationState? destination,
    Map<String, BigInt>? resolvedDirectorySizes,
  }) {
    return SendStateDrafting(
      items: items ?? this.items,
      destination: destination ?? this.destination,
      resolvedDirectorySizes:
          resolvedDirectorySizes ?? this.resolvedDirectorySizes,
    );
  }
}

class SendStateTransferring extends SendState {
  const SendStateTransferring({
    required this.items,
    required this.destination,
    required this.request,
    required this.transfer,
    this.resolvedDirectorySizes = const {},
  });

  final List<SendDraftItem> items;
  final SendDestinationState destination;
  final SendRequestData request;
  final SendTransferState transfer;
  final Map<String, BigInt> resolvedDirectorySizes;

  SendStateTransferring copyWith({
    List<SendDraftItem>? items,
    SendDestinationState? destination,
    SendRequestData? request,
    SendTransferState? transfer,
    Map<String, BigInt>? resolvedDirectorySizes,
  }) {
    return SendStateTransferring(
      items: items ?? this.items,
      destination: destination ?? this.destination,
      request: request ?? this.request,
      transfer: transfer ?? this.transfer,
      resolvedDirectorySizes:
          resolvedDirectorySizes ?? this.resolvedDirectorySizes,
    );
  }
}

class SendStateResult extends SendState {
  const SendStateResult({
    required this.items,
    required this.destination,
    required this.request,
    required this.transfer,
    required this.result,
    this.errorMessage,
    this.resolvedDirectorySizes = const {},
  });

  final List<SendDraftItem> items;
  final SendDestinationState destination;
  final SendRequestData request;
  final SendTransferState transfer;
  final SendTransferResult result;
  final String? errorMessage;
  final Map<String, BigInt> resolvedDirectorySizes;

  SendStateResult copyWith({
    List<SendDraftItem>? items,
    SendDestinationState? destination,
    SendRequestData? request,
    SendTransferState? transfer,
    SendTransferResult? result,
    String? errorMessage,
    Map<String, BigInt>? resolvedDirectorySizes,
  }) {
    return SendStateResult(
      items: items ?? this.items,
      destination: destination ?? this.destination,
      request: request ?? this.request,
      transfer: transfer ?? this.transfer,
      result: result ?? this.result,
      errorMessage: errorMessage ?? this.errorMessage,
      resolvedDirectorySizes:
          resolvedDirectorySizes ?? this.resolvedDirectorySizes,
    );
  }
}

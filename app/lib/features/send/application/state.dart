import 'package:flutter/foundation.dart';

import 'model.dart';

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
  }) : mode = SendDestinationMode.nearby,
       code = null;

  final SendDestinationMode mode;
  final String? code;
  final String? ticket;
  final String? lanDestinationLabel;
}

enum SendSessionPhase { idle, drafting, transferring, result }

@immutable
class SendState {
  const SendState._({
    required this.phase,
    required this.items,
    required this.destination,
    required this.request,
    required this.result,
    required this.errorMessage,
  });

  const SendState.idle()
      : this._(
          phase: SendSessionPhase.idle,
          items: const [],
          destination: const SendDestinationState.none(),
          request: null,
          result: null,
          errorMessage: null,
        );

  const SendState.drafting({
    required List<SendDraftItem> items,
    SendDestinationState destination = const SendDestinationState.none(),
  }) : this._(
         phase: SendSessionPhase.drafting,
         items: items,
         destination: destination,
         request: null,
         result: null,
         errorMessage: null,
       );

  const SendState.transferring({
    required List<SendDraftItem> items,
    required SendDestinationState destination,
    required SendRequestData request,
  }) : this._(
         phase: SendSessionPhase.transferring,
         items: items,
         destination: destination,
         request: request,
         result: null,
         errorMessage: null,
       );

  const SendState.result({
    required List<SendDraftItem> items,
    required SendDestinationState destination,
    required SendRequestData request,
    required SendTransferResult result,
    String? errorMessage,
  }) : this._(
         phase: SendSessionPhase.result,
         items: items,
         destination: destination,
         request: request,
         result: result,
         errorMessage: errorMessage,
       );

  final SendSessionPhase phase;
  final List<SendDraftItem> items;
  final SendDestinationState destination;
  final SendRequestData? request;
  final SendTransferResult? result;
  final String? errorMessage;
}

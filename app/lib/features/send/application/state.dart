import 'package:flutter/foundation.dart';

import 'model.dart';

enum SendSessionPhase { idle, drafting, transferring, result }

@immutable
class SendState {
  const SendState._({
    required this.phase,
    required this.items,
    required this.destination,
    required this.result,
    required this.errorMessage,
  });

  const SendState.idle()
      : this._(
          phase: SendSessionPhase.idle,
          items: const [],
          destination: null,
          result: null,
          errorMessage: null,
        );

  final SendSessionPhase phase;
  final List<SendDraftItem> items;
  final String? destination;
  final SendTransferResult? result;
  final String? errorMessage;
}


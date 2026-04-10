import 'package:flutter/material.dart';

enum TransferSessionPhase { idle, offerPending, receiving, completed, failed }

@immutable
class TransferIncomingOfferState {
  const TransferIncomingOfferState({
    required this.senderName,
  });

  final String senderName;

  String get displaySenderName {
    final value = senderName.trim();
    return value.isEmpty ? 'Nearby device' : value;
  }
}

@immutable
class TransfersServiceState {
  const TransfersServiceState({
    required this.phase,
    required this.incomingOffer,
  });

  const TransfersServiceState.idle()
      : phase = TransferSessionPhase.idle,
        incomingOffer = null;

  factory TransfersServiceState.offerPending({
    required String senderName,
  }) {
    return TransfersServiceState(
      phase: TransferSessionPhase.offerPending,
      incomingOffer: TransferIncomingOfferState(senderName: senderName),
    );
  }

  factory TransfersServiceState.receiving({
    required String senderName,
  }) {
    return TransfersServiceState(
      phase: TransferSessionPhase.receiving,
      incomingOffer: TransferIncomingOfferState(senderName: senderName),
    );
  }

  factory TransfersServiceState.completed({
    String? senderName,
  }) {
    return TransfersServiceState(
      phase: TransferSessionPhase.completed,
      incomingOffer: senderName == null
          ? null
          : TransferIncomingOfferState(senderName: senderName),
    );
  }

  factory TransfersServiceState.failed({
    String? senderName,
  }) {
    return TransfersServiceState(
      phase: TransferSessionPhase.failed,
      incomingOffer: senderName == null
          ? null
          : TransferIncomingOfferState(senderName: senderName),
    );
  }

  final TransferSessionPhase phase;
  final TransferIncomingOfferState? incomingOffer;

  bool get hasIncomingOffer => incomingOffer != null;
}

@immutable
class TransfersViewState {
  const TransfersViewState({
    required this.phase,
    required this.incomingOffer,
  });

  const TransfersViewState.empty()
      : phase = TransferSessionPhase.idle,
        incomingOffer = null;

  final TransferSessionPhase phase;
  final TransferIncomingOfferState? incomingOffer;

  bool get hasIncomingOffer => incomingOffer != null;
}

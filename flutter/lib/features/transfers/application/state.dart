import 'package:flutter/foundation.dart';

import 'identity.dart';
import 'manifest.dart';

enum TransferSessionPhase {
  idle,
  offerPending,
  receiving,
  completed,
  cancelled,
  failed,
}

@immutable
class TransferTransferProgress {
  const TransferTransferProgress({
    required this.bytesTransferred,
    required this.totalBytes,
    required this.completedFiles,
    required this.totalFiles,
    this.activeFileIndex,
    this.activeFileBytesTransferred,
    this.speedLabel,
    this.etaLabel,
  });

  final BigInt bytesTransferred;
  final BigInt totalBytes;
  final int completedFiles;
  final int totalFiles;
  final int? activeFileIndex;
  final BigInt? activeFileBytesTransferred;
  final String? speedLabel;
  final String? etaLabel;

  double get progressFraction {
    if (totalBytes == BigInt.zero) {
      return 0;
    }

    final transferred = bytesTransferred.toDouble();
    final total = totalBytes.toDouble();
    return transferred / total;
  }
}

@immutable
class TransferTransferResult {
  const TransferTransferResult({
    required this.bytesTransferred,
    required this.totalBytes,
    required this.completedFiles,
    required this.totalFiles,
    this.duration,
    this.averageSpeedLabel,
  });

  final BigInt bytesTransferred;
  final BigInt totalBytes;
  final int completedFiles;
  final int totalFiles;
  final Duration? duration;
  final String? averageSpeedLabel;
}

@immutable
class TransferIncomingOffer {
  const TransferIncomingOffer({
    required this.sender,
    required this.manifest,
    required this.destinationLabel,
    required this.saveRootLabel,
    required this.statusMessage,
    required this.bytesReceived,
  });

  final TransferIdentity sender;
  final TransferManifest manifest;
  final String destinationLabel;
  final String saveRootLabel;
  final String statusMessage;
  final BigInt bytesReceived;

  String get displaySenderName => sender.displayName;
  bool get willResume => bytesReceived > BigInt.zero;
}

@immutable
class TransferSessionState {
  const TransferSessionState._({
    required this.phase,
    required this.offer,
    required this.progress,
    required this.result,
    required this.errorMessage,
  });

  const TransferSessionState.idle()
    : this._(
        phase: TransferSessionPhase.idle,
        offer: null,
        progress: null,
        result: null,
        errorMessage: null,
      );

  const TransferSessionState.offerPending({
    required TransferIncomingOffer offer,
  }) : this._(
         phase: TransferSessionPhase.offerPending,
         offer: offer,
         progress: null,
         result: null,
         errorMessage: null,
       );

  const TransferSessionState.receiving({
    required TransferIncomingOffer offer,
    required TransferTransferProgress progress,
  }) : this._(
         phase: TransferSessionPhase.receiving,
         offer: offer,
         progress: progress,
         result: null,
         errorMessage: null,
       );

  const TransferSessionState.completed({
    required TransferIncomingOffer offer,
    required TransferTransferResult result,
  }) : this._(
         phase: TransferSessionPhase.completed,
         offer: offer,
         progress: null,
         result: result,
         errorMessage: null,
       );

  const TransferSessionState.cancelled({
    required TransferIncomingOffer offer,
    required String errorMessage,
  }) : this._(
         phase: TransferSessionPhase.cancelled,
         offer: offer,
         progress: null,
         result: null,
         errorMessage: errorMessage,
       );

  const TransferSessionState.failed({
    required TransferIncomingOffer offer,
    required String errorMessage,
  }) : this._(
         phase: TransferSessionPhase.failed,
         offer: offer,
         progress: null,
         result: null,
         errorMessage: errorMessage,
       );

  final TransferSessionPhase phase;
  final TransferIncomingOffer? offer;
  final TransferTransferProgress? progress;
  final TransferTransferResult? result;
  final String? errorMessage;

  bool get hasOffer => offer != null;
  bool get hasIncomingOffer => hasOffer;

  TransferIncomingOffer? get incomingOffer => offer;
}

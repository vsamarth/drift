import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/send_transfer_source.dart';
import '../../state/drift_app_state.dart';
import '../receive/receive_mapper.dart';
import 'send_dependencies.dart';
import '../../state/drift_sample_data.dart';
import 'send_flow_actions.dart' as send_flow_actions;
import 'send_mapper.dart' as send_mapper;
import 'send_session_reducer.dart';

abstract interface class SendSessionHost {
  DriftAppState get sendAppState;

  void setSendSession(ShellSessionState session);

  void clearNearbyScanTimer();

  void cancelActiveSendTransfer();

  void logSendTransferFailure(Object error, StackTrace stackTrace);
}

final sendSessionControllerProvider = Provider<SendSessionController>((ref) {
  return SendSessionController(
    transferSource: ref.watch(sendTransferSourceProvider),
  );
});

class SendSessionController {
  SendSessionController({required SendTransferSource transferSource})
    : _transferSource = transferSource;

  final SendTransferSource _transferSource;
  DateTime? _sendPayloadStartedAt;

  void applySendDraftSession(SendSessionHost host, SendDraftSession session) {
    host.setSendSession(session);
  }

  void clearSendFlow(SendSessionHost host) {
    host.clearNearbyScanTimer();
    host.cancelActiveSendTransfer();
    _sendPayloadStartedAt = null;
    host.setSendSession(const IdleSession());
  }

  void cancelSendInProgress(SendSessionHost host) {
    final next = send_flow_actions.markSendTransferCancelling(
      host.sendAppState.session,
    );
    if (next == null) {
      return;
    }
    host.setSendSession(next);
    unawaited(_cancelNativeSendTransfer(host));
  }

  void clearSendMetricState() {
    _sendPayloadStartedAt = null;
  }

  void applySendTransferUpdate(
    SendSessionHost host,
    SendTransferUpdate update,
  ) {
    final progress = progressFromSnapshot(update.snapshot);
    final bytesTransferred =
        progress.bytesTransferred ??
        (update.bytesSent > 0 ? update.bytesSent : null);
    if (_sendPayloadStartedAt == null && (bytesTransferred ?? 0) > 0) {
      _sendPayloadStartedAt = DateTime.now();
    }

    host.setSendSession(
      reduceSendTransferUpdate(
        state: host.sendAppState,
        update: update,
        payloadStartedAt: _sendPayloadStartedAt,
      ),
    );
  }

  Future<void> _cancelNativeSendTransfer(SendSessionHost host) async {
    try {
      await _transferSource.cancelTransfer();
    } catch (error, stackTrace) {
      debugPrint('cancelTransfer failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      host.logSendTransferFailure(error, stackTrace);
      applySendTransferUpdate(
        host,
        SendTransferUpdate(
          phase: SendTransferUpdatePhase.failed,
          destinationLabel:
              host.sendAppState.sendDestinationLabel ??
              send_mapper.formatCodeAsDestination(
                host.sendAppState.sendDestinationCode,
              ),
          statusMessage: 'Cancelling transfer...',
          itemCount: host.sendAppState.sendItems.length,
          totalSize:
              host.sendAppState.sendSummary?.totalSize ??
              sampleSendSummary.totalSize,
          bytesSent: host.sendAppState.sendPayloadBytesSent ?? 0,
          totalBytes: host.sendAppState.sendPayloadTotalBytes ?? 0,
          errorMessage: 'Drift couldn\'t cancel the transfer.',
        ),
      );
    }
  }
}

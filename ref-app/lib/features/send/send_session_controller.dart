import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/send_transfer_source.dart';
import '../receive/receive_mapper.dart';
import '../../state/shell_session_state.dart';
import '../../shared/logging/transfer_logging.dart';
import 'send_dependencies.dart';
import '../../state/drift_sample_data.dart';
import 'send_flow_state.dart';
import 'send_flow_actions.dart' as send_flow_actions;
import 'send_mapper.dart' as send_mapper;
import 'send_session_reducer.dart';
import 'send_state.dart';

abstract interface class SendSessionHost {
  SendState get sendState;

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
      host.sendState.session,
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
    switch (update.phase) {
      case SendTransferUpdatePhase.cancelled:
      case SendTransferUpdatePhase.failed:
        logTransferTerminalOutcome(
          scope: 'send',
          phase: update.phase.name,
          destinationLabel: update.destinationLabel,
          statusMessage: update.statusMessage,
          errorMessage: update.errorMessage,
        );
        break;
      case SendTransferUpdatePhase.connecting:
      case SendTransferUpdatePhase.waitingForDecision:
      case SendTransferUpdatePhase.accepted:
      case SendTransferUpdatePhase.declined:
      case SendTransferUpdatePhase.sending:
      case SendTransferUpdatePhase.completed:
        break;
    }
    final progress = progressFromSnapshot(update.snapshot);
    final bytesTransferred =
        progress.bytesTransferred ??
        (update.bytesSent > 0 ? update.bytesSent : null);
    if (_sendPayloadStartedAt == null && (bytesTransferred ?? 0) > 0) {
      _sendPayloadStartedAt = DateTime.now();
    }

    host.setSendSession(
      reduceSendTransferUpdate(
        state: host.sendState,
        update: update,
        payloadStartedAt: _sendPayloadStartedAt,
      ),
    );
  }

  Future<void> _cancelNativeSendTransfer(SendSessionHost host) async {
    try {
      await _transferSource.cancelTransfer();
    } catch (error, stackTrace) {
      logTransferError(
        scope: 'send',
        action: 'cancelTransfer',
        error: error,
        stackTrace: stackTrace,
      );
      host.logSendTransferFailure(error, stackTrace);
      applySendTransferUpdate(
        host,
        SendTransferUpdate(
          phase: SendTransferUpdatePhase.failed,
          destinationLabel:
              host.sendState.sendDestinationLabel ??
              send_mapper.formatCodeAsDestination(
                host.sendState.sendDestinationCode,
              ),
          statusMessage: 'Cancelling transfer...',
          itemCount: host.sendState.sendItems.length,
          totalSize:
              host.sendState.sendSummary?.totalSize ??
              sampleSendSummary.totalSize,
          bytesSent: host.sendState.sendPayloadBytesSent ?? 0,
          totalBytes: host.sendState.sendPayloadTotalBytes ?? 0,
          errorMessage: 'Drift couldn\'t cancel the transfer.',
        ),
      );
    }
  }
}

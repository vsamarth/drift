import 'package:drift_app/features/send/send_session_reducer.dart';
import 'package:drift_app/features/send/send_flow_state.dart';
import 'package:drift_app/features/send/send_state.dart';
import 'package:drift_app/platform/send_transfer_source.dart';
import 'package:drift_app/state/drift_app_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'send_test_support.dart';

void main() {
  test('connecting update becomes a send transfer session', () {
    final session = reduceSendTransferUpdate(
      state: SendState.fromAppState(buildSendDraftState()),
      update: const SendTransferUpdate(
        phase: SendTransferUpdatePhase.connecting,
        destinationLabel: 'Maya\'s iPhone',
        statusMessage: 'Connecting...',
        itemCount: 1,
        totalSize: '18 KB',
        bytesSent: 0,
        totalBytes: 18 * 1024,
      ),
      payloadStartedAt: null,
    );

    expect(session, isA<SendTransferSession>());
    final transferSession = session as SendTransferSession;
    expect(transferSession.phase, SendTransferSessionPhase.connecting);
    expect(transferSession.summary.destinationLabel, 'Maya\'s iPhone');
    expect(transferSession.items, hasLength(1));
  });

  test('completed update includes send completion metrics', () {
    final session = reduceSendTransferUpdate(
      state: SendState.fromAppState(buildSendDraftState()),
      update: const SendTransferUpdate(
        phase: SendTransferUpdatePhase.completed,
        destinationLabel: 'Maya\'s iPhone',
        statusMessage: 'Done',
        itemCount: 1,
        totalSize: '18 KB',
        bytesSent: 9 * 1024,
        totalBytes: 18 * 1024,
      ),
      payloadStartedAt: DateTime.now().subtract(const Duration(seconds: 1)),
    );

    expect(session, isA<SendResultSession>());
    final resultSession = session as SendResultSession;
    expect(resultSession.success, isTrue);
    expect(resultSession.outcome, TransferResultOutcomeData.success);
    expect(resultSession.metrics, isNotNull);
    expect(resultSession.metrics!.first.label, 'Sent to');
  });
}

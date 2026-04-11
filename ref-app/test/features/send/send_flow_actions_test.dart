import 'package:drift_app/core/models/transfer_models.dart';
import 'package:drift_app/features/send/send_flow_actions.dart' as send_flow_actions;
import 'package:drift_app/features/send/send_flow_state.dart';
import 'package:drift_app/state/transfer_result_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'send_test_support.dart';

void main() {
  test('buildSendStartIntent prefers a nearby ticket over manual code', () {
    final destination = const SendDestinationViewData(
      name: 'Lab Mac',
      kind: SendDestinationKind.laptop,
      lanTicket: 'ticket-123',
      lanFullname: 'lab-mac._drift._udp.local.',
    );
    final draft = (buildSendDraftState().session as SendDraftSession).copyWith(
      selectedDestination: destination,
      destinationCode: 'AB2CD3',
    );

    final intent = send_flow_actions.buildSendStartIntent(
      buildSendState(buildSendDraftState().copyWith(session: draft)),
    )!;

    expect(intent.ticket, 'ticket-123');
    expect(intent.destination, destination);
    expect(intent.normalizedCode, isNull);
  });

  test('buildSendStartIntent uses manual code when no nearby ticket is selected', () {
    final draft = (buildSendDraftState().session as SendDraftSession).copyWith(
      destinationCode: 'AB2CD3',
    );

    final intent = send_flow_actions.buildSendStartIntent(
      buildSendState(buildSendDraftState().copyWith(session: draft)),
    )!;

    expect(intent.normalizedCode, 'AB2CD3');
    expect(intent.ticket, isNull);
    expect(intent.destination, isNull);
  });

  test('sendPrimaryActionRoute maps send-again and choose-another actions', () {
    final sendAgain = send_flow_actions.sendPrimaryActionRoute(
      const TransferResultViewData(
        outcome: TransferResultOutcomeData.cancelled,
        title: 'Transfer cancelled',
        message: 'The transfer was stopped before all files were sent.',
        primaryAction: TransferResultPrimaryActionData.sendAgain,
      ),
    );

    final chooseAnother = send_flow_actions.sendPrimaryActionRoute(
      const TransferResultViewData(
        outcome: TransferResultOutcomeData.declined,
        title: 'Transfer declined',
        message: 'The receiving device chose not to accept this transfer.',
        primaryAction: TransferResultPrimaryActionData.chooseAnotherDevice,
      ),
    );

    expect(sendAgain, send_flow_actions.SendFlowRoute.restoreDraft);
    expect(chooseAnother, send_flow_actions.SendFlowRoute.returnToSelection);
  });

  test('sendGoBackRoute handles send draft and transfer sessions', () {
    final draft = buildSendDraftState().session as SendDraftSession;
    final transfer = buildSendTransferState().session as SendTransferSession;

    expect(
      send_flow_actions.sendGoBackRoute(draft),
      send_flow_actions.SendFlowRoute.resetShell,
    );
    expect(
      send_flow_actions.sendGoBackRoute(transfer),
      send_flow_actions.SendFlowRoute.returnToSelection,
    );
  });
}

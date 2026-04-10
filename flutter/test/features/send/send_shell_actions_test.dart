import 'package:drift_app/core/models/transfer_models.dart';
import 'package:drift_app/features/send/send_shell_actions.dart' as send_shell_actions;
import 'package:drift_app/state/drift_app_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'send_test_support.dart';

void main() {
  test('normalizes and stores a send destination code on the draft', () {
    final draft = send_shell_actions.updateSendDestinationCode(
      buildSendDraftState().session as SendDraftSession,
      'ab2-cd3',
    )!;

    expect(draft.destinationCode, 'AB2CD3');
    expect(draft.selectedDestination, isNull);
  });

  test('selecting the same nearby destination toggles it off', () {
    final destination = const SendDestinationViewData(
      name: 'Lab Mac',
      kind: SendDestinationKind.laptop,
      lanTicket: 'ticket-123',
      lanFullname: 'lab-mac._drift._udp.local.',
    );
    final draft = buildSendDraftState().session as SendDraftSession;
    final selected = draft.copyWith(selectedDestination: destination);

    final toggled = send_shell_actions.selectNearbyDestination(
      selected,
      destination,
    )!;

    expect(toggled.selectedDestination, isNull);
    expect(toggled.destinationCode, selected.destinationCode);
  });
}

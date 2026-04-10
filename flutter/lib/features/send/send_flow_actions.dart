import '../../core/models/transfer_models.dart';
import '../../state/drift_app_state.dart';

enum SendFlowRoute {
  none,
  resetShell,
  restoreDraft,
  returnToSelection,
}

class SendStartIntent {
  const SendStartIntent._({
    this.destination,
    this.ticket,
    this.normalizedCode,
  });

  const SendStartIntent.ticket({
    required SendDestinationViewData destination,
    required String ticket,
  }) : this._(destination: destination, ticket: ticket);

  const SendStartIntent.code(String normalizedCode)
    : this._(normalizedCode: normalizedCode);

  final SendDestinationViewData? destination;
  final String? ticket;
  final String? normalizedCode;
}

SendStartIntent? buildSendStartIntent(DriftAppState state) {
  final draft = state.session;
  if (draft is! SendDraftSession || draft.items.isEmpty || draft.isInspecting) {
    return null;
  }

  final selected = draft.selectedDestination;
  final ticket = selected?.lanTicket?.trim();
  if (selected != null && ticket != null && ticket.isNotEmpty) {
    return SendStartIntent.ticket(destination: selected, ticket: ticket);
  }

  if (draft.destinationCode.length == 6) {
    return SendStartIntent.code(draft.destinationCode);
  }

  return null;
}

SendFlowRoute sendPrimaryActionRoute(TransferResultViewData? result) {
  switch (result?.primaryAction) {
    case TransferResultPrimaryActionData.done:
    case null:
      return SendFlowRoute.resetShell;
    case TransferResultPrimaryActionData.tryAgain:
    case TransferResultPrimaryActionData.sendAgain:
      return SendFlowRoute.restoreDraft;
    case TransferResultPrimaryActionData.chooseAnotherDevice:
      return SendFlowRoute.returnToSelection;
  }
}

SendFlowRoute sendGoBackRoute(ShellSessionState session) {
  return switch (session) {
    SendDraftSession() => SendFlowRoute.resetShell,
    SendTransferSession() || SendResultSession() =>
      SendFlowRoute.returnToSelection,
    _ => SendFlowRoute.none,
  };
}

SendTransferSession? markSendTransferCancelling(ShellSessionState session) {
  if (session is! SendTransferSession) {
    return null;
  }
  return session.copyWith(
    phase: SendTransferSessionPhase.cancelling,
    summary: session.summary.copyWith(statusMessage: 'Cancelling transfer...'),
  );
}

ShellSessionState clearSendFlowSession() {
  return const IdleSession();
}

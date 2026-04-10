import '../core/models/transfer_models.dart';
import '../state/drift_app_state.dart';
import '../features/send/send_state.dart';

/// Maps controller state to a single shell “screen” for layout and transitions.
enum ShellView {
  sendIdle,
  sendSelected,
  sendReady,
  sendWaiting,
  sendCompleted,
  sendError,
  receiveReview,
  receiveReceiving,
  receiveCompleted,
}

ShellView shellViewFor(DriftAppState state) {
  final sendState = SendState(
    identity: state.identity,
    animateSendingConnection: state.animateSendingConnection,
    discoverableByDefault: state.discoverableByDefault,
    session: state.session,
  );
  if (sendState.mode == TransferDirection.receive) {
    return switch (state.receiveStage) {
      TransferStage.review => ShellView.receiveReview,
      TransferStage.waiting => ShellView.receiveReceiving,
      TransferStage.completed => ShellView.receiveCompleted,
      _ => ShellView.sendIdle,
    };
  }
  return switch (sendState.sendStage) {
    TransferStage.collecting => ShellView.sendSelected,
    TransferStage.ready => ShellView.sendReady,
    TransferStage.waiting => ShellView.sendWaiting,
    TransferStage.completed => ShellView.sendCompleted,
    TransferStage.error => ShellView.sendError,
    _ => ShellView.sendIdle,
  };
}

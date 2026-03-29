import '../core/models/transfer_models.dart';
import '../state/drift_controller.dart';

/// Maps controller state to a single shell “screen” for layout and transitions.
enum ShellView {
  sendIdle,
  sendSelected,
  sendReady,
  sendWaiting,
  sendCompleted,
  sendError,
  receiveEntry,
  receiveReview,
  receiveCompleted,
  receiveError,
}

ShellView shellViewFor(DriftController c) {
  if (c.mode == TransferDirection.receive) {
    return switch (c.receiveStage) {
      TransferStage.review => ShellView.receiveReview,
      TransferStage.completed => ShellView.receiveCompleted,
      TransferStage.error => ShellView.receiveError,
      _ => ShellView.receiveEntry,
    };
  }
  return switch (c.sendStage) {
    TransferStage.collecting => ShellView.sendSelected,
    TransferStage.ready => ShellView.sendReady,
    TransferStage.waiting => ShellView.sendWaiting,
    TransferStage.completed => ShellView.sendCompleted,
    TransferStage.error => ShellView.sendError,
    _ => ShellView.sendIdle,
  };
}

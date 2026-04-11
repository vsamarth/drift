import 'package:flutter/foundation.dart';

import '../core/models/transfer_models.dart';
import '../features/receive/receive_state.dart';
import '../features/send/send_state.dart';
import 'shell_routing.dart';

@immutable
class AppShellState {
  const AppShellState({
    required this.view,
    required this.canGoBack,
    required this.showBackButton,
  });

  final ShellView view;
  final bool canGoBack;
  final bool showBackButton;
}

AppShellState buildAppShellState({
  required SendState sendState,
  required ReceiveState receiveState,
}) {
  final view = _shellViewFor(sendState: sendState, receiveState: receiveState);
  return AppShellState(
    view: view,
    canGoBack: view != ShellView.sendIdle,
    showBackButton: _showBackButtonFor(view),
  );
}

ShellView _shellViewFor({
  required SendState sendState,
  required ReceiveState receiveState,
}) {
  return switch (receiveState.receiveStage) {
    TransferStage.review => ShellView.receiveReview,
    TransferStage.waiting => ShellView.receiveReceiving,
    TransferStage.completed => ShellView.receiveCompleted,
    _ => switch (sendState.sendStage) {
      TransferStage.collecting => ShellView.sendSelected,
      TransferStage.ready => ShellView.sendReady,
      TransferStage.waiting => ShellView.sendWaiting,
      TransferStage.completed => ShellView.sendCompleted,
      TransferStage.error => ShellView.sendError,
      _ => ShellView.sendIdle,
    },
  };
}

bool _showBackButtonFor(ShellView view) {
  return switch (view) {
    ShellView.sendIdle => false,
    ShellView.sendSelected => true,
    ShellView.sendReady => true,
    ShellView.sendWaiting => true,
    ShellView.sendCompleted => false,
    ShellView.sendError => true,
    ShellView.receiveReview => true,
    ShellView.receiveReceiving => false,
    ShellView.receiveCompleted => false,
  };
}

import '../src/rust/api/error.dart' as rust_error;

String bridgeErrorMessage(
  rust_error.BridgeError? error, {
  required String fallback,
}) {
  final message = switch (error?.kind) {
    rust_error.BridgeErrorKind.invalidInput => 'Invalid input',
    rust_error.BridgeErrorKind.invalidCode => 'Invalid pairing code',
    rust_error.BridgeErrorKind.rendezvousUnavailable =>
      'Could not reach the rendezvous server',
    rust_error.BridgeErrorKind.rendezvousRejected =>
      'Rendezvous server rejected the request',
    rust_error.BridgeErrorKind.peerNotFound => 'Peer not found',
    rust_error.BridgeErrorKind.peerAlreadyClaimed =>
      'That pairing code has already been used',
    rust_error.BridgeErrorKind.lanUnavailable => 'LAN discovery unavailable',
    rust_error.BridgeErrorKind.noNearbyReceivers =>
      'No nearby receivers found',
    rust_error.BridgeErrorKind.connectionFailed =>
      'Could not connect to the other device',
    rust_error.BridgeErrorKind.protocolViolation =>
      'Unexpected transfer state',
    rust_error.BridgeErrorKind.transferDeclined => 'Transfer declined',
    rust_error.BridgeErrorKind.transferCancelled => 'Transfer cancelled',
    rust_error.BridgeErrorKind.transferFailed => 'Transfer failed',
    rust_error.BridgeErrorKind.fileConflict => 'File conflict',
    rust_error.BridgeErrorKind.fileNotFound => 'File not found',
    rust_error.BridgeErrorKind.permissionDenied => 'Permission denied',
    rust_error.BridgeErrorKind.io => 'I/O error',
    rust_error.BridgeErrorKind.internal => 'Something went wrong',
    null => fallback,
  };

  final reason = error?.reason?.trim();
  if (reason == null || reason.isEmpty) {
    return message;
  }

  if (switch (error?.kind) {
    rust_error.BridgeErrorKind.internal ||
    rust_error.BridgeErrorKind.io ||
    rust_error.BridgeErrorKind.connectionFailed ||
    rust_error.BridgeErrorKind.rendezvousUnavailable ||
    rust_error.BridgeErrorKind.transferFailed => true,
    _ => false,
  }) {
    return '$message: $reason';
  }

  return message;
}

bool bridgeErrorIsCancelled(rust_error.BridgeError? error) =>
    error?.kind == rust_error.BridgeErrorKind.transferCancelled;

bool bridgeErrorIsDeclined(rust_error.BridgeError? error) =>
    error?.kind == rust_error.BridgeErrorKind.transferDeclined;

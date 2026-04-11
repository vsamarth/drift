import '../../../features/receive/application/state.dart';
import '../../../src/rust/api/receiver.dart' as rust_receiver;

ReceiverServiceState mapReceiverPairingState(
  rust_receiver.ReceiverPairingState state,
) {
  final code = (state.code ?? '').trim().toUpperCase();
  if (code.isEmpty) {
    return const ReceiverServiceState.unavailable();
  }

  return ReceiverServiceState.ready(code: code, expiresAt: state.expiresAt);
}

ReceiverServiceState mapReceiverRegistration(
  rust_receiver.ReceiverRegistration registration,
) {
  return ReceiverServiceState.ready(
    code: registration.code.trim().toUpperCase(),
    expiresAt: registration.expiresAt,
  );
}

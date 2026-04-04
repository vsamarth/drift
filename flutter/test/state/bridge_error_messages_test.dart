import 'package:drift_app/src/rust/api/error.dart' as rust_error;
import 'package:drift_app/state/bridge_error_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bridge error message maps common failure kinds', () {
    expect(
      bridgeErrorMessage(
        const rust_error.BridgeError(
          kind: rust_error.BridgeErrorKind.invalidCode,
        ),
        fallback: 'fallback',
      ),
      'Invalid pairing code',
    );

    expect(
      bridgeErrorMessage(
        const rust_error.BridgeError(
          kind: rust_error.BridgeErrorKind.transferCancelled,
        ),
        fallback: 'fallback',
      ),
      'Transfer cancelled',
    );

    expect(
      bridgeErrorMessage(
        const rust_error.BridgeError(
          kind: rust_error.BridgeErrorKind.transferFailed,
          reason: 'receiver declined the offer',
        ),
        fallback: 'fallback',
      ),
      'Transfer failed: receiver declined the offer',
    );
  });

  test('bridge error helpers classify terminal outcomes', () {
    expect(
      bridgeErrorIsCancelled(
        const rust_error.BridgeError(
          kind: rust_error.BridgeErrorKind.transferCancelled,
        ),
      ),
      isTrue,
    );
    expect(
      bridgeErrorIsDeclined(
        const rust_error.BridgeError(
          kind: rust_error.BridgeErrorKind.transferDeclined,
        ),
      ),
      isTrue,
    );
  });
}

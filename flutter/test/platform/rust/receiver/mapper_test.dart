import 'package:flutter_test/flutter_test.dart';

import 'package:app/platform/rust/receiver/mapper.dart';
import 'package:app/src/rust/api/receiver.dart' as rust_receiver;

void main() {
  test('maps an empty pairing state to an unavailable receiver state', () {
    final state = mapReceiverPairingState(
      const rust_receiver.ReceiverPairingState(),
    );

    expect(state.snapshot.hasRegistration, isFalse);
    expect(state.pairingCode.isAvailable, isFalse);
    expect(state.pairingCode.code, isNull);
  });

  test('maps a pairing code to a ready receiver state', () {
    final state = mapReceiverPairingState(
      const rust_receiver.ReceiverPairingState(
        code: 'abc123',
        expiresAt: '2099-01-01T00:00:00Z',
      ),
    );

    expect(state.snapshot.hasRegistration, isTrue);
    expect(state.pairingCode.isAvailable, isTrue);
    expect(state.pairingCode.code, 'ABC123');
    expect(state.pairingCode.formattedCode, 'ABC 123');
    expect(state.pairingCode.clipboardCode, 'ABC123');
  });

  test('maps a registration to a ready receiver state', () {
    final state = mapReceiverRegistration(
      const rust_receiver.ReceiverRegistration(
        code: 'abc123',
        expiresAt: '2099-01-01T00:00:00Z',
      ),
    );

    expect(state.snapshot.hasRegistration, isTrue);
    expect(state.pairingCode.code, 'ABC123');
    expect(state.pairingCode.isAvailable, isTrue);
    expect(state.pairingCode.clipboardCode, 'ABC123');
  });
}

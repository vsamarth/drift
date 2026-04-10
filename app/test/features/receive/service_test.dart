import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/features/receive/feature.dart';
import 'package:app/platform/rust/receiver/fake_source.dart';

void main() {
  test('receiver service tracks the source state', () async {
    final source = FakeReceiverServiceSource(
      initialState: ReceiverServiceState.ready(code: 'ABC123'),
    );
    final container = ProviderContainer(
      overrides: [
        receiverServiceSourceProvider.overrideWithValue(source),
      ],
    );
    addTearDown(container.dispose);

    final initial = container.read(receiverServiceProvider);
    expect(initial.pairingCode.code, 'ABC123');
    expect(initial.snapshot.hasRegistration, isTrue);

    source.emit(const ReceiverServiceState.unavailable());
    await Future<void>.delayed(Duration.zero);

    final updated = container.read(receiverServiceProvider);
    expect(updated.pairingCode.isAvailable, isFalse);
    expect(updated.snapshot.hasRegistration, isFalse);
  });
}

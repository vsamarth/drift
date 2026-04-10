import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/features/receive/feature.dart';

void main() {
  test('receiver service cycles badge states', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final initial = container.read(receiverServiceProvider);
    expect(initial.snapshot.lifecycle, ReceiverLifecycle.ready);
    expect(initial.pairingCode.code, 'ABC123');

    container.read(receiverServiceProvider.notifier).advanceDemoState();
    final unavailable = container.read(receiverServiceProvider);
    expect(unavailable.snapshot.lifecycle, ReceiverLifecycle.ready);
    expect(unavailable.pairingCode.isAvailable, isFalse);

    container.read(receiverServiceProvider.notifier).advanceDemoState();
    final registering = container.read(receiverServiceProvider);
    expect(registering.snapshot.lifecycle, ReceiverLifecycle.starting);
    expect(registering.pairingCode.isAvailable, isFalse);

    container.read(receiverServiceProvider.notifier).advanceDemoState();
    final readyAgain = container.read(receiverServiceProvider);
    expect(readyAgain.snapshot.lifecycle, ReceiverLifecycle.ready);
    expect(readyAgain.pairingCode.code, 'ABC123');
  });
}

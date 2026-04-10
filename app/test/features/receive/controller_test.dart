import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/receive/feature.dart';

void main() {
  test('maps a registering receiver to the registering badge', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(receiverServiceProvider.notifier);
    notifier.advanceDemoState();
    notifier.advanceDemoState();

    final state = container.read(receiverIdleViewStateProvider);

    expect(state.badge.label, 'Registering');
    expect(state.badge.phase, ReceiverBadgePhase.registering);
    expect(state.code, '......');
  });
}

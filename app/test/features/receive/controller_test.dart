import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/receive/feature.dart';
import 'package:app/features/settings/feature.dart';
import 'package:app/platform/rust/receiver/fake_source.dart';
import '../../support/settings_test_overrides.dart';

void main() {
  test('maps a registering receiver to the registering badge', () {
    final container = ProviderContainer(
      overrides: [
        initialAppSettingsProvider.overrideWithValue(testAppSettings),
        receiverServiceSourceProvider.overrideWithValue(
          FakeReceiverServiceSource(
            initialState: const ReceiverServiceState.registering(),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final state = container.read(receiverIdleViewStateProvider);

    expect(state.badge.label, 'Registering');
    expect(state.badge.phase, ReceiverBadgePhase.registering);
    expect(state.code, '......');
  });

}

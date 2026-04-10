import 'package:drift_app/shell/shell_routing.dart';
import 'package:drift_app/shell/app_shell_providers.dart';
import 'package:drift_app/state/app_identity.dart';
import 'package:drift_app/state/drift_app_state.dart';
import 'package:drift_app/state/drift_providers.dart';
import 'package:drift_app/state/receiver_service_source.dart';
import 'package:drift_app/state/settings_store.dart';
import 'package:drift_app/src/rust/api/receiver.dart' as rust_receiver;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy app coordinator remains a transitional compatibility layer', () {
    // Phase 0/1 rule: keep the legacy coordinator alive only as a bridge
    // while feature ownership moves out into smaller modules.
    final container = ProviderContainer(
      overrides: [
        driftSettingsStoreProvider.overrideWith(
          (ref) => DriftSettingsStore.inMemory(),
        ),
        initialDriftAppIdentityProvider.overrideWith(
          (ref) => const DriftAppIdentity(
            deviceName: 'Drift Device',
            deviceType: 'laptop',
            downloadRoot: '/tmp/Downloads',
          ),
        ),
        receiverServiceSourceProvider.overrideWith(
          (ref) => const _NoopReceiverServiceSource(),
        ),
        enableIdleIncomingListenerProvider.overrideWith((ref) => false),
      ],
    );
    addTearDown(container.dispose);

    final state = container.read(driftAppNotifierProvider);

    expect(state.session, isA<IdleSession>());
    expect(state.receiverBadge.phase, ReceiverBadgePhase.registering);
    expect(container.read(appShellStateProvider).view, ShellView.sendIdle);
    expect(container.read(appShellStateProvider).canGoBack, isFalse);
    expect(container.read(appShellStateProvider).showBackButton, isFalse);
  });
}

class _NoopReceiverServiceSource implements ReceiverServiceSource {
  const _NoopReceiverServiceSource();

  @override
  Stream<ReceiverBadgeState> watchBadge(DriftAppIdentity identity) {
    return const Stream<ReceiverBadgeState>.empty();
  }

  @override
  Stream<rust_receiver.ReceiverTransferEvent> watchIncomingTransfers(
    DriftAppIdentity identity,
  ) {
    return const Stream<rust_receiver.ReceiverTransferEvent>.empty();
  }

  @override
  Future<void> cancelTransfer() async {}

  @override
  Future<void> respondToOffer({required bool accept}) async {}

  @override
  Future<void> setDiscoverable({required bool enabled}) async {}
}

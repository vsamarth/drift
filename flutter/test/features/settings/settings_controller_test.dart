import 'package:drift_app/features/settings/settings_providers.dart';
import 'package:drift_app/state/app_identity.dart';
import 'package:drift_app/state/drift_dependencies.dart';
import 'package:drift_app/state/settings_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ProviderContainer _buildContainer({
  DriftSettingsStore? store,
  DriftAppIdentity? initialIdentity,
}) {
  return ProviderContainer(
    overrides: [
      driftSettingsStoreProvider.overrideWith(
        (ref) => store ?? DriftSettingsStore.inMemory(),
      ),
      initialDriftAppIdentityProvider.overrideWith(
        (ref) =>
            initialIdentity ??
            const DriftAppIdentity(
              deviceName: 'Drift Device',
              deviceType: 'laptop',
              downloadRoot: '/tmp/Downloads',
              discoverableByDefault: true,
              serverUrl: 'https://drift.samarthv.com',
            ),
      ),
    ],
  );
}

void main() {
  test('saveSettings persists changes and updates feature state', () async {
    final store = DriftSettingsStore.inMemory();
    final container = _buildContainer(store: store);
    addTearDown(container.dispose);

    final controller = container.read(settingsControllerProvider.notifier);
    await controller.saveSettings(
      deviceName: 'My MacBook',
      downloadRoot: '/Users/me/Downloads/Drift',
      discoverableByDefault: false,
      serverUrl: 'https://example.test',
    );

    final state = container.read(settingsControllerProvider);
    expect(state.identity.deviceName, 'My MacBook');
    expect(state.identity.downloadRoot, '/Users/me/Downloads/Drift');
    expect(state.identity.discoverableByDefault, isFalse);
    expect(state.identity.serverUrl, 'https://example.test');
    expect(await store.load(), state.identity);
  });

  test('saveSettings short-circuits when nothing changed', () async {
    final container = _buildContainer();
    addTearDown(container.dispose);

    final before = container.read(settingsControllerProvider);
    await container
        .read(settingsControllerProvider.notifier)
        .saveSettings(
          deviceName: before.identity.deviceName,
          downloadRoot: before.identity.downloadRoot,
          discoverableByDefault: before.identity.discoverableByDefault,
          serverUrl: before.identity.serverUrl,
        );

    final after = container.read(settingsControllerProvider);
    expect(after.identity, before.identity);
    expect(after.isSaving, isFalse);
    expect(after.errorMessage, isNull);
  });
}

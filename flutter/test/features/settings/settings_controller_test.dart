import 'package:app/features/settings/feature.dart';
import 'package:app/features/receive/application/service.dart';
import 'package:app/platform/rust/receiver/fake_source.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('starts from the seeded settings', () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = SettingsRepository(
      prefs: prefs,
      randomDeviceName: () => 'Rusty Ridge',
      defaultDownloadRoot: '/tmp/Drift',
    );
    final initialSettings = await repo.loadOrCreate();
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(repo),
        initialAppSettingsProvider.overrideWithValue(initialSettings),
      ],
    );
    addTearDown(container.dispose);

    final state = container.read(settingsControllerProvider);

    expect(state.settings.deviceName, 'Rusty Ridge');
    expect(state.settings.downloadRoot, '/tmp/Drift');
    expect(state.settings.discoverableByDefault, isTrue);
    expect(state.settings.discoveryServerUrl, isNull);
  });

  test('saveSettings updates the stored settings', () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = SettingsRepository(
      prefs: prefs,
      randomDeviceName: () => 'Rusty Ridge',
      defaultDownloadRoot: '/tmp/Drift',
    );
    final initialSettings = await repo.loadOrCreate();
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(repo),
        initialAppSettingsProvider.overrideWithValue(initialSettings),
      ],
    );
    addTearDown(container.dispose);

    await container.read(settingsControllerProvider.notifier).saveSettings(
          deviceName: 'Maya MacBook',
          downloadRoot: '/Users/maya/Downloads',
          serverUrl: 'https://example.com',
          discoverableByDefault: false,
        );

    final state = container.read(settingsControllerProvider);

    expect(state.settings.deviceName, 'Maya MacBook');
    expect(state.settings.downloadRoot, '/Users/maya/Downloads');
    expect(state.settings.discoverableByDefault, isFalse);
    expect(state.settings.discoveryServerUrl, 'https://example.com');
    expect(prefs.getString('settings.device_name'), 'Maya MacBook');
    expect(prefs.getString('settings.download_root'), '/Users/maya/Downloads');
    expect(prefs.getBool('settings.discoverable'), isFalse);
    expect(prefs.getString('settings.server_url'), 'https://example.com');
  });

  test('saveSettings refreshes the live receiver identity', () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = SettingsRepository(
      prefs: prefs,
      randomDeviceName: () => 'Rusty Ridge',
      defaultDownloadRoot: '/tmp/Drift',
    );
    final initialSettings = await repo.loadOrCreate();
    final receiverSource = FakeReceiverServiceSource();
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(repo),
        initialAppSettingsProvider.overrideWithValue(initialSettings),
        receiverServiceSourceProvider.overrideWithValue(receiverSource),
      ],
    );
    addTearDown(container.dispose);

    await container.read(settingsControllerProvider.notifier).saveSettings(
          deviceName: 'Maya MacBook',
          downloadRoot: '/Users/maya/Downloads',
          serverUrl: 'https://example.com',
          discoverableByDefault: false,
        );

    expect(receiverSource.lastUpdatedDeviceName, 'Maya MacBook');
    expect(receiverSource.lastUpdatedServerUrl, 'https://example.com');
  });
}

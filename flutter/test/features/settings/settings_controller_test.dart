import 'package:app/features/settings/feature.dart';
import 'package:app/features/receive/application/service.dart';
import 'package:app/platform/rust/receiver/fake_source.dart';
import 'package:app/platform/rust/rendezvous_defaults.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

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
    expect(state.settings.discoveryServerUrl, defaultRendezvousUrl);
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

    await container
        .read(settingsControllerProvider.notifier)
        .saveSettings(
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

    await container
        .read(settingsControllerProvider.notifier)
        .saveSettings(
          deviceName: 'Maya MacBook',
          downloadRoot: '/Users/maya/Downloads',
          serverUrl: 'https://example.com',
          discoverableByDefault: false,
        );

    expect(receiverSource.lastUpdatedDeviceName, 'Maya MacBook');
    expect(receiverSource.lastUpdatedServerUrl, 'https://example.com');
  });

  test('concurrent saveSettings keeps only the latest completion', () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = _DelayedSettingsRepository(prefs: prefs);
    final receiverSource = FakeReceiverServiceSource();
    const initialSettings = AppSettings(
      deviceName: 'Seed',
      downloadRoot: '/tmp/Drift',
      discoverableByDefault: true,
      discoveryServerUrl: null,
    );
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(repo),
        initialAppSettingsProvider.overrideWithValue(initialSettings),
        receiverServiceSourceProvider.overrideWithValue(receiverSource),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(settingsControllerProvider.notifier);
    final firstSave = controller.saveSettings(
      deviceName: 'First Device',
      downloadRoot: '/tmp/first',
      serverUrl: '',
      discoverableByDefault: true,
    );
    final secondSave = controller.saveSettings(
      deviceName: 'Second Device',
      downloadRoot: '/tmp/second',
      serverUrl: 'https://two.example',
      discoverableByDefault: false,
    );

    expect(repo.saveCallCount, 2);

    repo.completeSave(1);
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(settingsControllerProvider).settings.deviceName,
      'Second Device',
    );

    repo.completeSave(0);
    await Future.wait([firstSave, secondSave]);

    final finalState = container.read(settingsControllerProvider);
    expect(finalState.settings.deviceName, 'Second Device');
    expect(finalState.settings.downloadRoot, '/tmp/second');
    expect(finalState.settings.discoveryServerUrl, 'https://two.example');
    expect(receiverSource.lastUpdatedDeviceName, 'Second Device');
    expect(receiverSource.lastUpdatedServerUrl, 'https://two.example');
  });

  test(
    'saveSettings keeps memory aligned with persisted settings when live update fails',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = SettingsRepository(
        prefs: prefs,
        randomDeviceName: () => 'Rusty Ridge',
        defaultDownloadRoot: '/tmp/Drift',
      );
      final initialSettings = await repo.loadOrCreate();
      final receiverSource = _FailingIdentityReceiverSource();
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(repo),
          initialAppSettingsProvider.overrideWithValue(initialSettings),
          receiverServiceSourceProvider.overrideWithValue(receiverSource),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(settingsControllerProvider.notifier)
          .saveSettings(
            deviceName: 'Maya MacBook',
            downloadRoot: '/Users/maya/Downloads',
            serverUrl: 'https://example.com',
            discoverableByDefault: false,
          );

      final state = container.read(settingsControllerProvider);
      expect(state.settings.deviceName, 'Maya MacBook');
      expect(state.settings.downloadRoot, '/Users/maya/Downloads');
      expect(state.settings.discoveryServerUrl, 'https://example.com');
      expect(state.errorMessage, isNotNull);
      expect(prefs.getString('settings.device_name'), 'Maya MacBook');
      expect(
        prefs.getString('settings.download_root'),
        '/Users/maya/Downloads',
      );
      expect(prefs.getString('settings.server_url'), 'https://example.com');
    },
  );
}

class _DelayedSettingsRepository extends SettingsRepository {
  _DelayedSettingsRepository({required super.prefs})
    : super(randomDeviceName: () => 'Seed', defaultDownloadRoot: '/tmp/Drift');

  final List<Completer<void>> _saveCompleters = <Completer<void>>[];
  int saveCallCount = 0;

  @override
  Future<void> save(AppSettings settings) {
    saveCallCount += 1;
    final completer = Completer<void>();
    _saveCompleters.add(completer);
    return completer.future;
  }

  void completeSave(int index) {
    _saveCompleters[index].complete();
  }
}

class _FailingIdentityReceiverSource extends FakeReceiverServiceSource {
  @override
  Future<void> updateIdentity({
    required String deviceName,
    required String downloadRoot,
    String? serverUrl,
  }) async {
    throw Exception('live update failed');
  }
}

import 'package:app/features/settings/application/repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('loadOrCreate seeds defaults when preferences are empty', () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = SettingsRepository(
      prefs: prefs,
      randomDeviceName: () => 'Rusty Ridge',
      defaultDownloadRoot: '/tmp/Drift',
    );

    final settings = await repo.loadOrCreate();

    expect(settings.deviceName, 'Rusty Ridge');
    expect(settings.downloadRoot, '/tmp/Drift');
    expect(settings.discoverableByDefault, isTrue);
    expect(settings.discoveryServerUrl, isNull);
  });
}

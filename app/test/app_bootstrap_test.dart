import 'package:app/app/app_bootstrap.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('bootstrap creates seeded settings on first launch', () async {
    final bootstrap = await loadAppBootstrap(
      randomDeviceName: () => 'Rusty Ridge',
      defaultDownloadRoot: '/tmp/Drift',
    );

    expect(bootstrap.initialSettings.deviceName, 'Rusty Ridge');
    expect(bootstrap.initialSettings.downloadRoot, '/tmp/Drift');
    expect(bootstrap.initialSettings.discoverableByDefault, isTrue);
    expect(bootstrap.initialSettings.discoveryServerUrl, isNull);
  });
}

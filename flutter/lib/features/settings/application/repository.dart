import 'package:shared_preferences/shared_preferences.dart';

import '../../../platform/rust/rendezvous_defaults.dart';
import 'state.dart';

const String _deviceNameKey = 'settings.device_name';
const String _downloadRootKey = 'settings.download_root';
const String _discoverableKey = 'settings.discoverable';
const String _serverUrlKey = 'settings.server_url';

class SettingsRepository {
  SettingsRepository({
    required this.prefs,
    required this.randomDeviceName,
    required this.defaultDownloadRoot,
  });

  final SharedPreferences prefs;
  final String Function() randomDeviceName;
  final String defaultDownloadRoot;

  Future<AppSettings> loadOrCreate() async {
    final existing = _readExisting();
    if (existing != null) {
      return existing;
    }

    final seeded = AppSettings(
      deviceName: randomDeviceName(),
      downloadRoot: defaultDownloadRoot,
      discoverableByDefault: true,
      discoveryServerUrl: defaultRendezvousUrl,
    );
    await save(seeded);
    return seeded;
  }

  Future<void> save(AppSettings settings) async {
    await prefs.setString(_deviceNameKey, settings.deviceName);
    await prefs.setString(_downloadRootKey, settings.downloadRoot);
    await prefs.setBool(_discoverableKey, settings.discoverableByDefault);
    if (settings.discoveryServerUrl == null ||
        settings.discoveryServerUrl!.trim().isEmpty) {
      await prefs.remove(_serverUrlKey);
    } else {
      await prefs.setString(_serverUrlKey, settings.discoveryServerUrl!.trim());
    }
  }

  AppSettings? _readExisting() {
    if (!prefs.containsKey(_deviceNameKey) ||
        !prefs.containsKey(_downloadRootKey)) {
      return null;
    }

    return AppSettings(
      deviceName: prefs.getString(_deviceNameKey) ?? randomDeviceName(),
      downloadRoot: prefs.getString(_downloadRootKey) ?? defaultDownloadRoot,
      discoverableByDefault: prefs.getBool(_discoverableKey) ?? true,
      discoveryServerUrl:
          _normalizeUrl(prefs.getString(_serverUrlKey)) ?? defaultRendezvousUrl,
    );
  }
}

String? _normalizeUrl(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

import 'package:shared_preferences/shared_preferences.dart';

import 'app_identity.dart';

class DriftSettingsStore {
  DriftSettingsStore(this._prefs) : _memory = null;

  DriftSettingsStore.inMemory() : _prefs = null, _memory = <String, Object?>{};

  static const _deviceNameKey = 'settings.device_name';
  static const _downloadRootKey = 'settings.download_root';
  static const _serverUrlKey = 'settings.server_url';
  static const _discoverableKey = 'settings.discoverable';

  final SharedPreferences? _prefs;
  final Map<String, Object?>? _memory;

  bool _containsKey(String key) {
    return _prefs?.containsKey(key) ?? _memory!.containsKey(key);
  }

  String? _getString(String key) {
    return _prefs?.getString(key) ?? _memory?[key] as String?;
  }

  bool? _getBool(String key) {
    return _prefs?.getBool(key) ?? _memory?[key] as bool?;
  }

  Future<DriftAppIdentity> initialize() async {
    final rawDeviceName = _getString(_deviceNameKey);
    final rawDownloadRoot = _getString(_downloadRootKey);
    final rawServerUrl = _getString(_serverUrlKey);
    final rawDiscoverable = _getBool(_discoverableKey);

    final identity = buildDefaultDriftAppIdentity(
      deviceName: rawDeviceName,
      downloadRoot: rawDownloadRoot,
      serverUrl: rawServerUrl,
      discoverable: rawDiscoverable,
    );

    final shouldPersist =
        !_containsKey(_deviceNameKey) ||
        !_containsKey(_downloadRootKey) ||
        !_containsKey(_discoverableKey) ||
        rawDeviceName != identity.deviceName ||
        rawDownloadRoot != identity.downloadRoot ||
        normalizeServerUrl(rawServerUrl) != identity.serverUrl;

    if (shouldPersist) {
      await save(identity);
    }

    return identity;
  }

  DriftAppIdentity load() {
    return buildDefaultDriftAppIdentity(
      deviceName: _getString(_deviceNameKey),
      downloadRoot: _getString(_downloadRootKey),
      serverUrl: _getString(_serverUrlKey),
      discoverable: _getBool(_discoverableKey),
    );
  }

  Future<void> save(DriftAppIdentity identity) async {
    final prefs = _prefs;
    if (prefs != null) {
      await prefs.setString(_deviceNameKey, identity.deviceName);
      await prefs.setString(_downloadRootKey, identity.downloadRoot);
    } else {
      _memory![_deviceNameKey] = identity.deviceName;
      _memory[_downloadRootKey] = identity.downloadRoot;
    }

    final serverUrl = identity.serverUrl?.trim();
    if (serverUrl == null || serverUrl.isEmpty) {
      if (prefs != null) {
        await prefs.remove(_serverUrlKey);
      } else {
        _memory!.remove(_serverUrlKey);
      }
    } else {
      if (prefs != null) {
        await prefs.setString(_serverUrlKey, serverUrl);
      } else {
        _memory![_serverUrlKey] = serverUrl;
      }
    }

    if (prefs != null) {
      await prefs.setBool(_discoverableKey, identity.discoverableByDefault);
    } else {
      _memory![_discoverableKey] = identity.discoverableByDefault;
    }
  }
}

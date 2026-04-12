import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings_providers.dart';
import 'state.dart';
import '../../receive/application/service.dart';

final settingsControllerProvider =
    NotifierProvider<SettingsController, SettingsState>(SettingsController.new);

class SettingsController extends Notifier<SettingsState> {
  int _saveRequestSerial = 0;

  @override
  SettingsState build() {
    return SettingsState(settings: ref.watch(initialAppSettingsProvider));
  }

  Future<void> saveSettings({
    required String deviceName,
    required String downloadRoot,
    required String serverUrl,
    required bool discoverableByDefault,
  }) async {
    final repository = ref.read(settingsRepositoryProvider);
    final receiverSource = ref.read(receiverServiceSourceProvider);
    final requestSerial = ++_saveRequestSerial;
    final baseSettings = state.settings;
    final nextSettings = state.settings.copyWith(
      deviceName: _normalizeDeviceName(deviceName, baseSettings),
      downloadRoot: downloadRoot.trim(),
      discoverableByDefault: discoverableByDefault,
      discoveryServerUrl: _normalizeServerUrl(serverUrl),
    );

    debugPrint(
      '[settings] save requested '
      'device="${nextSettings.deviceName}" '
      'downloadRoot="${nextSettings.downloadRoot}" '
      'serverUrl="${nextSettings.discoveryServerUrl ?? ""}" '
      'discoverable=${nextSettings.discoverableByDefault}',
    );
    state = state.copyWith(isSaving: true, clearErrorMessage: true);
    try {
      await repository.save(nextSettings);
      if (!_isLatestSave(requestSerial)) {
        return;
      }
      final identityChanged =
          nextSettings.deviceName != baseSettings.deviceName ||
          nextSettings.downloadRoot != baseSettings.downloadRoot ||
          nextSettings.discoveryServerUrl != baseSettings.discoveryServerUrl;
      String? syncError;
      if (identityChanged) {
        debugPrint(
          '[settings] live receiver update '
          'device="${nextSettings.deviceName}" '
          'downloadRoot="${nextSettings.downloadRoot}" '
          'serverUrl="${nextSettings.discoveryServerUrl ?? ""}"',
        );
        try {
          await receiverSource.updateIdentity(
            deviceName: nextSettings.deviceName,
            downloadRoot: nextSettings.downloadRoot,
            serverUrl: nextSettings.discoveryServerUrl,
          );
          debugPrint('[settings] live receiver update complete');
        } catch (error) {
          syncError = error.toString();
        }
      } else {
        debugPrint('[settings] live receiver unchanged; skipped rebuild');
      }
      if (!_isLatestSave(requestSerial)) {
        return;
      }
      state = state.copyWith(
        settings: nextSettings,
        isSaving: false,
        errorMessage: syncError,
        clearErrorMessage: syncError == null,
      );
    } catch (error) {
      if (!_isLatestSave(requestSerial)) {
        return;
      }
      state = state.copyWith(isSaving: false, errorMessage: error.toString());
    }
  }

  bool _isLatestSave(int serial) => serial == _saveRequestSerial;

  String _normalizeDeviceName(String value, AppSettings fallback) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? fallback.deviceName : trimmed;
  }

  String? _normalizeServerUrl(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

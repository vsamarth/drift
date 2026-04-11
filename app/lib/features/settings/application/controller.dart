import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings_providers.dart';
import 'state.dart';
import '../../receive/application/service.dart';

final settingsControllerProvider =
    NotifierProvider<SettingsController, SettingsState>(
      SettingsController.new,
    );

class SettingsController extends Notifier<SettingsState> {
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
    final nextSettings = state.settings.copyWith(
      deviceName: _normalizeDeviceName(deviceName),
      downloadRoot: downloadRoot.trim(),
      discoverableByDefault: discoverableByDefault,
      discoveryServerUrl: _normalizeServerUrl(serverUrl),
    );

    state = state.copyWith(isSaving: true, clearErrorMessage: true);
    try {
      await repository.save(nextSettings);
      await receiverSource.updateIdentity(
        deviceName: nextSettings.deviceName,
        serverUrl: nextSettings.discoveryServerUrl,
      );
      state = state.copyWith(
        settings: nextSettings,
        isSaving: false,
        clearErrorMessage: true,
      );
    } catch (error) {
      state = state.copyWith(
        isSaving: false,
        errorMessage: error.toString(),
      );
    }
  }

  String _normalizeDeviceName(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? state.settings.deviceName : trimmed;
  }

  String? _normalizeServerUrl(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

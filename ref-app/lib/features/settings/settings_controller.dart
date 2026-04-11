import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_identity.dart';
import '../../state/drift_dependencies.dart';
import 'settings_providers.dart';
import 'settings_repository.dart';
import 'settings_state.dart';

class SettingsController extends Notifier<SettingsState> {
  late final SettingsRepository _repository;

  @override
  SettingsState build() {
    _repository = ref.watch(settingsRepositoryProvider);
    return SettingsState(identity: ref.watch(initialDriftAppIdentityProvider));
  }

  Future<void> saveSettings({
    required String deviceName,
    required String downloadRoot,
    required bool discoverableByDefault,
    String? serverUrl,
  }) async {
    final nextIdentity = buildDefaultDriftAppIdentity(
      deviceName: deviceName,
      deviceType: state.identity.deviceType,
      downloadRoot: downloadRoot,
      serverUrl: serverUrl,
      discoverable: discoverableByDefault,
    );

    if (nextIdentity == state.identity) {
      return;
    }

    state = state.copyWith(isSaving: true, clearErrorMessage: true);
    try {
      await _repository.save(nextIdentity);
      state = state.copyWith(
        identity: nextIdentity,
        isSaving: false,
        clearErrorMessage: true,
      );
    } catch (error) {
      state = state.copyWith(isSaving: false, errorMessage: error.toString());
      rethrow;
    }
  }
}

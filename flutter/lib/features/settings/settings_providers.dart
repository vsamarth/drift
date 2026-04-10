import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/drift_dependencies.dart';
import 'settings_controller.dart';
import 'settings_repository.dart';
import 'settings_state.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(ref.watch(driftSettingsStoreProvider));
});

final settingsControllerProvider =
    NotifierProvider<SettingsController, SettingsState>(SettingsController.new);

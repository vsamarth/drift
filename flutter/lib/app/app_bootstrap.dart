import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../platform/platform_features.dart';
import '../platform/storage_access_source.dart';
import '../state/app_identity.dart';
import '../state/settings_store.dart';
import '../src/rust/frb_generated.dart';

class DriftAppBootstrap {
  const DriftAppBootstrap({
    required this.settingsStore,
    required this.initialIdentity,
    required this.storageAccessSource,
  });

  final DriftSettingsStore settingsStore;
  final DriftAppIdentity initialIdentity;
  final StorageAccessSource storageAccessSource;
}

Future<DriftAppBootstrap> bootstrapDriftApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (isDesktopPlatform) {
    await windowManager.ensureInitialized();
  }
  await RustLib.init();

  final prefs = await SharedPreferences.getInstance();
  final settingsStore = DriftSettingsStore(prefs);
  final initialIdentity = await settingsStore.initialize();
  final storageAccessSource = StorageAccessSource();
  await storageAccessSource.restorePersistedAccess(
    path: initialIdentity.downloadRoot,
  );

  return DriftAppBootstrap(
    settingsStore: settingsStore,
    initialIdentity: initialIdentity,
    storageAccessSource: storageAccessSource,
  );
}

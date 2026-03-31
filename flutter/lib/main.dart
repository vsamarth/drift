import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'app/drift_app.dart';
import 'platform/storage_access_source.dart';
import 'platform/platform_features.dart';
import 'state/drift_dependencies.dart';
import 'state/settings_store.dart';
import 'src/rust/frb_generated.dart';

Future<void> main() async {
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

  runApp(
    ProviderScope(
      overrides: [
        driftSettingsStoreProvider.overrideWithValue(settingsStore),
        initialDriftAppIdentityProvider.overrideWithValue(initialIdentity),
        storageAccessSourceProvider.overrideWithValue(storageAccessSource),
      ],
      child: const DriftApp(),
    ),
  );
}

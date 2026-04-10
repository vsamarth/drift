import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/drift_dependencies.dart';
import 'app_bootstrap.dart';

List<Override> buildDriftAppOverrides(DriftAppBootstrap bootstrap) {
  return [
    driftSettingsStoreProvider.overrideWithValue(bootstrap.settingsStore),
    initialDriftAppIdentityProvider.overrideWithValue(
      bootstrap.initialIdentity,
    ),
    storageAccessSourceProvider.overrideWithValue(
      bootstrap.storageAccessSource,
    ),
  ];
}

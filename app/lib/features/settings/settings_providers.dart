import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application/repository.dart';
import 'application/state.dart';
import '../../platform/storage_access_source.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  throw UnimplementedError(
    'settingsRepositoryProvider must be overridden at bootstrap',
  );
});

final initialAppSettingsProvider = Provider<AppSettings>((ref) {
  throw UnimplementedError(
    'initialAppSettingsProvider must be overridden at bootstrap',
  );
});

final storageAccessSourceProvider = Provider<StorageAccessSource>((ref) {
  return const StorageAccessSource();
});

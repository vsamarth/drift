import '../../state/app_identity.dart';
import '../../state/settings_store.dart';

class SettingsRepository {
  const SettingsRepository(this._store);

  final DriftSettingsStore _store;

  Future<DriftAppIdentity> load() {
    return _store.initialize();
  }

  Future<void> save(DriftAppIdentity identity) {
    return _store.save(identity);
  }
}

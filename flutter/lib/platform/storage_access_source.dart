import 'package:file_selector/file_selector.dart';

class StorageAccessSource {
  const StorageAccessSource();

  Future<String?> pickDirectory({String? initialDirectory}) async {
    return getDirectoryPath(
      initialDirectory: initialDirectory,
      confirmButtonText: 'Choose folder',
    );
  }

  Future<void> restorePersistedAccess({required String path}) async {
    // No-op: Sandboxing has been disabled so security-scoped bookmarks are no longer needed.
  }
}

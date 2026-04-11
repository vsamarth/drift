import 'package:file_selector/file_selector.dart';

class StorageAccessSource {
  const StorageAccessSource();

  Future<String?> pickDirectory({String? initialDirectory}) async {
    return getDirectoryPath(
      initialDirectory: initialDirectory,
      confirmButtonText: 'Choose folder',
      canCreateDirectories: true,
    );
  }
}

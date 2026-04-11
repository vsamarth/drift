import 'package:drift_app/platform/storage_access_source.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeFileSelectorPlatform extends FileSelectorPlatform {
  FileDialogOptions? lastDirectoryOptions;
  String? nextDirectoryResult;

  @override
  Future<String?> getDirectoryPathWithOptions(FileDialogOptions options) async {
    lastDirectoryOptions = options;
    return nextDirectoryResult;
  }
}

void main() {
  test('pickDirectory uses the system directory picker', () async {
    final originalPlatform = FileSelectorPlatform.instance;
    final fakePlatform = FakeFileSelectorPlatform()
      ..nextDirectoryResult = '/storage/emulated/0/Download/Drift';

    FileSelectorPlatform.instance = fakePlatform;
    addTearDown(() {
      FileSelectorPlatform.instance = originalPlatform;
    });

    final source = StorageAccessSource();
    final result = await source.pickDirectory(
      initialDirectory: '/storage/emulated/0/Download',
    );

    expect(result, '/storage/emulated/0/Download/Drift');
    expect(fakePlatform.lastDirectoryOptions, isNotNull);
    expect(
      fakePlatform.lastDirectoryOptions!.initialDirectory,
      '/storage/emulated/0/Download',
    );
    expect(
      fakePlatform.lastDirectoryOptions!.confirmButtonText,
      'Choose folder',
    );
    expect(fakePlatform.lastDirectoryOptions!.canCreateDirectories, isTrue);
  });
}

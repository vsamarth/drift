import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'model.dart';

abstract class SendSelectionPicker {
  Future<List<SendPickedFile>> pickFiles();

  Future<List<SendPickedFile>> pickFolder();
}

final sendSelectionPickerProvider = Provider<SendSelectionPicker>((_) {
  return FileSelectorSendSelectionPicker();
});

class FileSelectorSendSelectionPicker implements SendSelectionPicker {
  @override
  Future<List<SendPickedFile>> pickFiles() async {
    final pickedFiles = await openFiles();
    return Future.wait(
      pickedFiles.map((file) async {
        final path = file.path.isNotEmpty ? file.path : file.name;
        BigInt? sizeBytes;
        try {
          sizeBytes = BigInt.from(await file.length());
        } catch (_) {
          sizeBytes = null;
        }
        return SendPickedFile(
          path: path,
          name: file.name.trim().isEmpty
              ? SendPickedFile.fromPath(path).name
              : file.name,
          kind: SendPickedFileKind.file,
          sizeBytes: sizeBytes,
        );
      }),
    );
  }

  @override
  Future<List<SendPickedFile>> pickFolder() async {
    final path = await getDirectoryPath();
    if (path == null || path.isEmpty) {
      return const [];
    }

    return [
      SendPickedFile(
        path: path,
        name: SendPickedFile.directory(path).name,
        kind: SendPickedFileKind.directory,
      ),
    ];
  }
}

import 'package:app/features/send/application/model.dart';
import 'package:app/features/send/application/send_selection_picker.dart';

class FakeSendSelectionPicker implements SendSelectionPicker {
  FakeSendSelectionPicker({
    this.filesResult = const [],
    this.folderResult = const [],
  });

  final List<SendPickedFile> filesResult;
  final List<SendPickedFile> folderResult;
  int filesPickCount = 0;
  int folderPickCount = 0;

  @override
  Future<List<SendPickedFile>> pickFiles() async {
    filesPickCount += 1;
    return filesResult;
  }

  @override
  Future<List<SendPickedFile>> pickFolder() async {
    folderPickCount += 1;
    return folderResult;
  }
}

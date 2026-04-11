import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/send/application/model.dart';

void main() {
  test('SendPickedFile.fromPath marks files and directories correctly', () async {
    final file = File('${Directory.systemTemp.path}/drift-send-file.txt');
    await file.writeAsString('hello');
    final dir = await Directory.systemTemp.createTemp('drift-send-dir');

    final pickedFile = SendPickedFile.fromPath(file.path);
    final pickedDir = SendPickedFile.fromPath(dir.path);

    expect(pickedFile.kind, SendPickedFileKind.file);
    expect(pickedFile.sizeBytes, isNull);
    expect(pickedDir.kind, SendPickedFileKind.directory);
    expect(pickedDir.sizeBytes, isNull);
  });
}

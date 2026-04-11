import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/send/application/model.dart';

void main() {
  test('SendPickedFile constructors preserve path, name, and kind', () async {
    final file = File('${Directory.systemTemp.path}/drift-send-file.txt');
    await file.writeAsString('hello');
    final dir = await Directory.systemTemp.createTemp('drift-send-dir');

    final pickedFile = SendPickedFile.fromPath(file.path);
    final pickedDir = SendPickedFile.directory(dir.path);

    expect(pickedFile.path, file.path);
    expect(pickedFile.name, 'drift-send-file.txt');
    expect(pickedFile.kind, SendPickedFileKind.file);
    expect(pickedFile.sizeBytes, isNull);
    expect(pickedDir.path, dir.path);
    expect(pickedDir.name, dir.path.split(Platform.pathSeparator).last);
    expect(pickedDir.kind, SendPickedFileKind.directory);
    expect(pickedDir.sizeBytes, isNull);
  });
}

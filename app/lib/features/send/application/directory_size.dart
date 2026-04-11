import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class DirectorySizeCalculator {
  Future<BigInt> sizeOfDirectory(String path);
}

final directorySizeCalculatorProvider = Provider<DirectorySizeCalculator>((_) {
  return const FileSystemDirectorySizeCalculator();
});

class FileSystemDirectorySizeCalculator implements DirectorySizeCalculator {
  const FileSystemDirectorySizeCalculator();

  @override
  Future<BigInt> sizeOfDirectory(String path) async {
    final directory = Directory(path);
    if (!await directory.exists()) {
      return BigInt.zero;
    }

    BigInt total = BigInt.zero;
    try {
      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) {
          try {
            total += BigInt.from(await entity.length());
          } catch (_) {
            // Ignore files that disappear or become unreadable mid-scan.
          }
        }
      }
    } catch (_) {
      return total;
    }

    return total;
  }
}

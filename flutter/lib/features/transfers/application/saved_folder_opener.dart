import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:io';

typedef SavedFolderOpener = Future<void> Function(String path);

final transferTargetPlatformProvider = Provider<TargetPlatform>((ref) {
  return defaultTargetPlatform;
});

final savedFolderOpenerProvider = Provider<SavedFolderOpener>((ref) {
  return openSavedFolder;
});

bool canOpenSavedFolder({TargetPlatform? platform}) {
  final targetPlatform = platform ?? defaultTargetPlatform;
  return switch (targetPlatform) {
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux => true,
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.fuchsia => false,
  };
}

String savedFolderOpenLabel({TargetPlatform? platform}) {
  final targetPlatform = platform ?? defaultTargetPlatform;
  return switch (targetPlatform) {
    TargetPlatform.macOS => 'Show in Finder',
    TargetPlatform.windows => 'Show in Explorer',
    TargetPlatform.linux => 'Show in Files',
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.fuchsia => 'Open folder',
  };
}

Future<void> openSavedFolder(String path) async {
  final trimmed = path.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(path, 'path', 'must not be empty');
  }

  if (Platform.isMacOS) {
    await Process.start('open', [trimmed]);
    return;
  }

  if (Platform.isWindows) {
    await Process.start('explorer', [trimmed]);
    return;
  }

  if (Platform.isLinux) {
    await Process.start('xdg-open', [trimmed]);
    return;
  }

  throw UnsupportedError('Opening saved folders is not supported here.');
}

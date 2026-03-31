import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

class StorageAccessSource {
  StorageAccessSource({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'drift/storage_access';

  final MethodChannel _channel;

  Future<String?> pickDirectory({String? initialDirectory}) async {
    if (Platform.isMacOS) {
      return _channel.invokeMethod<String>('pickDirectory', <String, Object?>{
        'initialDirectory': initialDirectory,
      });
    }

    return getDirectoryPath(
      initialDirectory: initialDirectory,
      confirmButtonText: 'Choose folder',
    );
  }

  Future<void> restorePersistedAccess({required String path}) async {
    if (!Platform.isMacOS || path.trim().isEmpty) {
      return;
    }
    await _channel.invokeMethod<void>(
      'restorePersistedAccess',
      <String, Object?>{'path': path},
    );
  }
}

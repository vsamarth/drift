import 'package:flutter/services.dart';

/// Calls a native Android [MethodChannel] that streams picked files to the
/// app cache directory and returns file-system paths.  This avoids the
/// [file_selector_android] bug (versions <= 0.5.2+x) where the entire file
/// is read into a [Uint8List] and encoded through the platform channel,
/// causing [OutOfMemoryError] for large files.
class AndroidFilePicker {
  static const MethodChannel _channel = MethodChannel(
    'com.example.drift/file_picker',
  );

  /// Opens the system file picker and returns a list of absolute paths to
  /// copies of the selected files stored in the app cache directory.
  static Future<List<String>> pickFiles() async {
    final result = await _channel.invokeMethod<List<dynamic>>('pickFiles');
    return result?.cast<String>() ?? const [];
  }
}

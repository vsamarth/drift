import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// Best-effort: raise and focus the app window when an incoming transfer needs attention.
///
/// Desktop only. May not steal focus in all OS policies or sandbox settings.
Future<void> focusAppForIncomingTransfer() async {
  if (kIsWeb) {
    return;
  }
  if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) {
    return;
  }
  try {
    await windowManager.show();
    await windowManager.focus();
  } catch (e, st) {
    debugPrint('focusAppForIncomingTransfer: $e');
    debugPrintStack(stackTrace: st);
  }
}

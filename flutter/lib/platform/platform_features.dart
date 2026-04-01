import 'dart:io';

import 'package:flutter/foundation.dart';

bool get isDesktopPlatform {
  if (kIsWeb) {
    return false;
  }
  return Platform.isMacOS || Platform.isWindows || Platform.isLinux;
}

bool get isMobilePlatform {
  if (kIsWeb) {
    return false;
  }
  return Platform.isAndroid || Platform.isIOS;
}

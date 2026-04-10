import 'package:flutter/material.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';

import 'app/app.dart';

void main() {
  const initialSize = Size(440, 560);
  appWindow.size = initialSize;
  runApp(const DriftApp());
  doWhenWindowReady(() {
    final win = appWindow;
    win.minSize = initialSize;
    win.maxSize = initialSize;
    win.size = initialSize;
    win.alignment = Alignment.center;
    win.title = 'Drift';
    win.show();
  });
}

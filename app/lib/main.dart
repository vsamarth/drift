import 'package:app/platform/rust/receiver/rust_source.dart';
import 'package:flutter/material.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'features/receive/feature.dart';
import 'features/transfers/feature.dart';
import 'src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();

  const initialSize = Size(440, 560);
  appWindow.size = initialSize;
  const rustSource = RustReceiverServiceSource();
  runApp(
    ProviderScope(
      overrides: [
        receiverServiceSourceProvider.overrideWithValue(
          rustSource,
        ),
        transfersServiceSourceProvider.overrideWithValue(
          rustSource,
        ),
      ],
      child: const DriftApp(),
    ),
  );
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

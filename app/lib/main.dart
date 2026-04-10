import 'dart:io';

import 'package:app/platform/rust/receiver/rust_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'features/receive/feature.dart';
import 'features/transfers/feature.dart';
import 'src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    await windowManager.ensureInitialized();
  }
  await RustLib.init();

  const initialSize = Size(440, 560);
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
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        size: initialSize,
        minimumSize: initialSize,
        maximumSize: initialSize,
        center: true,
        title: 'Drift',
      ),
      () async {
        await windowManager.show();
      },
    );
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';

import 'app/app_bootstrap.dart';
import 'app/app_providers.dart';
import 'app/drift_app.dart';

Future<void> main() async {
  final bootstrap = await bootstrapDriftApp();
  runApp(
    ProviderScope(
      overrides: buildDriftAppOverrides(bootstrap),
      child: const DriftApp(),
    ),
  );
}

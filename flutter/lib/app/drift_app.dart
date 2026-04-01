import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/drift_theme.dart';
import '../platform/platform_features.dart';
import '../shell/mobile_shell.dart';
import '../shell/utility_shell.dart';

class DriftApp extends ConsumerWidget {
  const DriftApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Drift',
      debugShowCheckedModeBanner: false,
      theme: buildDriftTheme(),
      home: isMobilePlatform ? const MobileShell() : const UtilityShell(),
    );
  }
}

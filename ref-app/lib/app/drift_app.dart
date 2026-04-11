import 'package:flutter/material.dart';

import '../core/theme/drift_theme.dart';
import '../platform/platform_features.dart';
import '../shell/mobile_shell.dart';
import '../shell/utility_shell.dart';

class DriftApp extends StatelessWidget {
  const DriftApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Drift',
      debugShowCheckedModeBanner: false,
      theme: buildDriftTheme(),
      home: isMobilePlatform ? const MobileShell() : const UtilityShell(),
    );
  }
}

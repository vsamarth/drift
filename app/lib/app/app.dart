import 'package:flutter/material.dart';

import '../shell/drift_shell.dart';
import '../theme/drift_theme.dart';

class DriftApp extends StatelessWidget {
  const DriftApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Drift',
      debugShowCheckedModeBanner: false,
      theme: buildDriftTheme(),
      home: const DriftShell(),
    );
  }
}

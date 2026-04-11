import 'package:flutter/material.dart';

import 'app_router.dart';
import '../theme/drift_theme.dart';

class DriftApp extends StatelessWidget {
  const DriftApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Drift',
      debugShowCheckedModeBanner: false,
      theme: buildDriftTheme(),
      routerConfig: buildAppRouter(),
    );
  }
}

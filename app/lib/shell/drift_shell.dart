import 'package:flutter/material.dart';

import '../features/receive/feature.dart';
import '../theme/drift_theme.dart';

class DriftShell extends StatelessWidget {
  const DriftShell({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: ReceiveFeature(),
      ),
    );
  }
}

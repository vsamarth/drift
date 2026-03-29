import 'package:flutter/material.dart';

import '../../core/theme/drift_theme.dart';
import '../../state/drift_controller.dart';

class ShellHeader extends StatelessWidget {
  const ShellHeader({super.key, required this.controller});

  final DriftController controller;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: GestureDetector(
        onTap: controller.resetShell,
        child: Text(
          'Start over',
          style: driftSans(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: kMuted,
          ),
        ),
      ),
    );
  }
}

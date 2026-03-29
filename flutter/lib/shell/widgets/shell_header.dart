import 'package:flutter/material.dart';

import '../../core/theme/drift_theme.dart';
import '../../state/drift_controller.dart';

class ShellHeader extends StatelessWidget {
  const ShellHeader({super.key, required this.controller});

  final DriftController controller;

  @override
  Widget build(BuildContext context) {
    if (!controller.showShellBackButton) {
      return const SizedBox.shrink();
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: IconButton(
        key: const ValueKey<String>('shell-back-button'),
        onPressed: controller.canGoBack ? controller.goBack : null,
        tooltip: 'Back',
        style: IconButton.styleFrom(
          foregroundColor: kMuted.withValues(alpha: 0.92),
          minimumSize: const Size(30, 30),
          padding: const EdgeInsets.all(6),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
      ),
    );
  }
}

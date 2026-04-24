import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class TitleBarShell extends StatelessWidget {
  const TitleBarShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDesktop =
        Platform.isMacOS || Platform.isWindows || Platform.isLinux;

    return Scaffold(
      body: Column(
        children: [
          if (isDesktop)
            const DragToMoveArea(
              child: SizedBox(height: 32, width: double.infinity),
            ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

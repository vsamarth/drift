import 'package:flutter/material.dart';

import 'drift_controller.dart';
import 'drift_theme.dart';
import 'widgets/desktop_shell.dart';

class DriftApp extends StatefulWidget {
  const DriftApp({super.key, DriftController? controller})
    : controller = controller;

  final DriftController? controller;

  @override
  State<DriftApp> createState() => _DriftAppState();
}

class _DriftAppState extends State<DriftApp> {
  late final DriftController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? DriftController();
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'drift',
      debugShowCheckedModeBanner: false,
      theme: buildDriftTheme(),
      home: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return DesktopShell(controller: _controller);
        },
      ),
    );
  }
}

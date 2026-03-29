import 'package:flutter/material.dart';

import '../core/theme/drift_theme.dart';
import '../shell/utility_shell.dart';
import '../state/drift_controller.dart';

class DriftApp extends StatefulWidget {
  const DriftApp({super.key, this.controller});

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
      title: 'Drift',
      debugShowCheckedModeBanner: false,
      theme: buildDriftTheme(),
      home: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return UtilityShell(controller: _controller);
        },
      ),
    );
  }
}

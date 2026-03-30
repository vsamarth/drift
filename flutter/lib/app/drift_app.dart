import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/drift_theme.dart';
import '../shell/utility_shell.dart';
import '../state/drift_controller.dart';
import '../state/drift_providers.dart';

class DriftApp extends StatefulWidget {
  const DriftApp({super.key, this.controller});

  final DriftController? controller;

  @override
  State<DriftApp> createState() => _DriftAppState();
}

class _DriftAppState extends State<DriftApp> {
  @override
  void dispose() {
    if (widget.controller != null) {
      // Tests can still inject a controller directly, and this widget remains
      // responsible for that lifecycle while it is mounted.
      widget.controller!.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Drift',
      debugShowCheckedModeBanner: false,
      theme: buildDriftTheme(),
      home: widget.controller == null
          ? Consumer(
              builder: (context, ref, _) {
                final controller = ref.watch(driftControllerProvider);
                ref.listen(
                  receiverServiceControllerProvider.select(
                    (service) => service.badgeState,
                  ),
                  (_, next) {
                    controller.syncReceiverBadge(
                      code: next.code,
                      status: next.status,
                    );
                  },
                );
                ref.watch(receiverServiceControllerProvider);
                return AnimatedBuilder(
                  animation: controller,
                  builder: (context, _) {
                    return UtilityShell(controller: controller);
                  },
                );
              },
            )
          : AnimatedBuilder(
              animation: widget.controller!,
              builder: (context, _) {
                return UtilityShell(controller: widget.controller!);
              },
            ),
    );
  }
}

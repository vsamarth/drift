import 'package:flutter/material.dart';

import '../core/theme/drift_theme.dart';
import '../state/drift_controller.dart';
import 'shell_routing.dart';
import 'widgets/mode_tabs.dart';
import 'widgets/shell_header.dart';
import 'widgets/shell_state_content.dart';

/// Primary window layout: mode tabs + state panel.
class UtilityShell extends StatelessWidget {
  const UtilityShell({super.key, required this.controller});

  final DriftController controller;

  @override
  Widget build(BuildContext context) {
    final view = shellViewFor(controller);

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final panelH =
                constraints.maxHeight > 640 ? 640.0 : constraints.maxHeight;

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: SizedBox(
                  height: panelH,
                  child: Padding(
                    key: const ValueKey<String>('utility-shell'),
                    padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (controller.hasActiveTransferCard) ...[
                          ShellHeader(controller: controller),
                          const SizedBox(height: 12),
                        ],
                        ModeTabs(controller: controller),
                        const SizedBox(height: 12),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (ctx, constraints) => AnimatedSwitcher(
                              duration: const Duration(milliseconds: 260),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              transitionBuilder: (child, anim) =>
                                  FadeTransition(opacity: anim, child: child),
                              child: ShellStateContent(
                                key: ValueKey<String>('state-${view.name}'),
                                controller: controller,
                                view: view,
                                availableHeight: constraints.maxHeight,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

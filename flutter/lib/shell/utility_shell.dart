import 'package:flutter/material.dart';

import '../core/theme/drift_theme.dart';
import '../state/drift_controller.dart';
import 'shell_routing.dart';
import 'widgets/idle_identity_zone.dart';
import 'widgets/shell_header.dart';
import 'widgets/shell_state_content.dart';

/// Primary window layout: a calm idle identity zone plus the active state panel.
class UtilityShell extends StatefulWidget {
  const UtilityShell({super.key, required this.controller});

  final DriftController controller;

  @override
  State<UtilityShell> createState() => _UtilityShellState();
}

class _UtilityShellState extends State<UtilityShell> {
  bool _idleWindowHovering = false;

  void _setIdleWindowHovering(bool value) {
    if (_idleWindowHovering == value) {
      return;
    }
    setState(() => _idleWindowHovering = value);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final view = shellViewFor(controller);
    final isIdle = view == ShellView.sendIdle;

    return Scaffold(
      backgroundColor: kBg,
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        color: isIdle && _idleWindowHovering ? const Color(0xFFF2F2F2) : kBg,
        child: SafeArea(
          child: MouseRegion(
            onEnter: isIdle ? (_) => _setIdleWindowHovering(true) : null,
            onExit: isIdle ? (_) => _setIdleWindowHovering(false) : null,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final panelH = constraints.maxHeight > 660
                    ? 660.0
                    : constraints.maxHeight;

                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: SizedBox(
                      height: panelH,
                      child: Padding(
                        key: const ValueKey<String>('utility-shell'),
                        padding: EdgeInsets.fromLTRB(
                          20,
                          isIdle ? 28 : 40,
                          20,
                          20,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (isIdle) ...[
                              IdleIdentityZone(controller: controller),
                              const SizedBox(height: 8),
                            ] else ...[
                              ShellHeader(controller: controller),
                              const SizedBox(height: 12),
                            ],
                            Expanded(
                              child: LayoutBuilder(
                                builder: (ctx, constraints) => AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 260),
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeInCubic,
                                  transitionBuilder: (child, anim) =>
                                      FadeTransition(
                                        opacity: anim,
                                        child: child,
                                      ),
                                  child: ShellStateContent(
                                    key: ValueKey<String>('state-${view.name}'),
                                    controller: controller,
                                    view: view,
                                    availableHeight: constraints.maxHeight,
                                    idleWindowHovering: _idleWindowHovering,
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
        ),
      ),
    );
  }
}

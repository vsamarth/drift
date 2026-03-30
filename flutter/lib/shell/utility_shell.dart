import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/drift_theme.dart';
import '../state/drift_providers.dart';
import 'widgets/idle_identity_zone.dart';
import 'widgets/shell_header.dart';
import 'widgets/shell_state_content.dart';

/// Primary window layout: a calm idle identity zone plus the active state panel.
class UtilityShell extends ConsumerStatefulWidget {
  const UtilityShell({super.key});

  @override
  ConsumerState<UtilityShell> createState() => _UtilityShellState();
}

class _UtilityShellState extends ConsumerState<UtilityShell> {
  bool _idleWindowHovering = false;

  void _setIdleWindowHovering(bool value) {
    if (_idleWindowHovering == value) {
      return;
    }
    setState(() => _idleWindowHovering = value);
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(shellViewProvider);
    final isIdle = view.name == 'sendIdle';

    return Scaffold(
      backgroundColor: kBg,
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        color: kBg,
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
                          isIdle ? 28 : 26,
                          20,
                          20,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (isIdle) ...[
                              const IdleIdentityZone(),
                              const SizedBox(height: 8),
                            ] else ...[
                              const ShellHeader(),
                              const SizedBox(height: 6),
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

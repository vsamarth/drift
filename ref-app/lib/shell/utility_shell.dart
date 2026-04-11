import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/drift_theme.dart';
import '../features/settings/widgets/settings_panel.dart';
import 'app_shell_providers.dart';
import 'shell_routing.dart';
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
  bool _showSettings = false;

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(appShellStateProvider).view;
    final isIdle = view == ShellView.sendIdle;
    final showSettings = isIdle && _showSettings;

    return Scaffold(
      backgroundColor: kBg,
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        color: kBg,
        child: SafeArea(
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
                        showSettings || isIdle ? 28 : 26,
                        20,
                        20,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showSettings) ...[
                            ShellHeader(
                              title: 'Settings',
                              forceShowBackButton: true,
                              onBackPressed: () {
                                setState(() => _showSettings = false);
                              },
                            ),
                            const SizedBox(height: 10),
                          ] else if (isIdle) ...[
                            IdleIdentityZone(
                              onOpenSettings: () {
                                setState(() => _showSettings = true);
                              },
                            ),
                            const SizedBox(height: 20),
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
                                    FadeTransition(opacity: anim, child: child),
                                child: ShellStateContent(
                                  key: ValueKey<String>('state-${view.name}'),
                                  view: view,
                                  availableHeight: constraints.maxHeight,
                                  overrideChild: showSettings
                                      ? SettingsPanel(
                                          availableHeight:
                                              constraints.maxHeight,
                                        )
                                      : null,
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
    );
  }
}

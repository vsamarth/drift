import 'package:flutter/material.dart';

import '../drift_controller.dart';
import '../models.dart';
import 'receive_workspace.dart';
import 'send_workspace.dart';

class DesktopShell extends StatelessWidget {
  const DesktopShell({super.key, required this.controller});

  final DriftController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 1120,
                  minHeight: 820,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFFAF9F6), Color(0xFFF2F0EA)],
                      ),
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(color: theme.colorScheme.outline),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 30,
                          offset: const Offset(0, 18),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
                      child: Column(
                        children: [
                          _TopBar(
                            controller: controller,
                            wideLayout: constraints.maxWidth >= 760,
                          ),
                          const SizedBox(height: 24),
                          Expanded(child: _buildWorkspace()),
                        ],
                      ),
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

  Widget _buildWorkspace() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: controller.mode == TransferDirection.send
          ? SendWorkspace(
              key: const ValueKey('send-workspace'),
              controller: controller,
            )
          : ReceiveWorkspace(
              key: const ValueKey('receive-workspace'),
              controller: controller,
            ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller, required this.wideLayout});

  final DriftController controller;
  final bool wideLayout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('drift', style: theme.textTheme.headlineMedium),
        const SizedBox(height: 4),
        Text(
          'Short-code file transfers for the calm side of desktop.',
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );

    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ModeSegmentedControl(controller: controller),
        const SizedBox(width: 16),
        IconButton(
          tooltip: 'Settings coming later',
          onPressed: () {},
          icon: const Icon(Icons.more_horiz_rounded),
        ),
      ],
    );

    if (wideLayout) {
      return Row(
        children: [
          Expanded(child: titleBlock),
          controls,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [titleBlock, const SizedBox(height: 16), controls],
    );
  }
}

class _ModeSegmentedControl extends StatelessWidget {
  const _ModeSegmentedControl({required this.controller});

  final DriftController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget segment(TransferDirection direction, IconData icon, String label) {
      final selected = controller.mode == direction;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: FilledButton.tonalIcon(
            key: ValueKey<String>('mode-$label'),
            style: FilledButton.styleFrom(
              backgroundColor: selected
                  ? theme.colorScheme.primary
                  : Colors.transparent,
              foregroundColor: selected
                  ? Colors.white
                  : theme.colorScheme.onSurface,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            onPressed: () => controller.setMode(direction),
            icon: Icon(icon, size: 18),
            label: Text(label),
          ),
        ),
      );
    }

    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Row(
        children: [
          segment(TransferDirection.send, Icons.north_east_rounded, 'Send'),
          segment(
            TransferDirection.receive,
            Icons.south_west_rounded,
            'Receive',
          ),
        ],
      ),
    );
  }
}

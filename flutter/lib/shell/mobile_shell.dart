import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/drift_theme.dart';
import 'app_shell_providers.dart';
import 'shell_routing.dart';
import '../state/drift_providers.dart';
import '../features/send/send_providers.dart';
import '../features/settings/widgets/mobile_settings_page.dart';
import 'widgets/mobile/mobile_identity_card.dart';
import 'widgets/mobile/select_files_card.dart';
import 'widgets/shell_header.dart';
import 'widgets/shell_state_content.dart';

class MobileShell extends ConsumerStatefulWidget {
  const MobileShell({super.key});

  @override
  ConsumerState<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends ConsumerState<MobileShell> {
  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (context) => const MobileSettingsPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shellState = ref.watch(appShellStateProvider);
    final state = ref.watch(driftAppNotifierProvider);
    final sendState = ref.watch(sendStateProvider);
    final notifier = ref.read(sendControllerProvider.notifier);
    final isIdle = shellState.view == ShellView.sendIdle;

    return Scaffold(
      backgroundColor: kBg,
      body: Stack(
        children: [
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(
                      children: [
                        const Spacer(),
                        IconButton(
                          onPressed: _openSettings,
                          icon: const Icon(Icons.tune_rounded),
                          tooltip: 'Settings',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    const SizedBox(height: 8),
                    MobileIdentityCard(
                      deviceName: state.deviceName,
                      receiveCode: state.idleReceiveCode,
                      status: state.idleReceiveStatus,
                      statusColor: state.receiverBadge.statusColor,
                    ),
                    const SizedBox(height: 32),
                    if (isIdle) ...[
                      SelectFilesCard(
                        onTap: notifier.pickSendItems,
                        isPicking: sendState.isInspectingSendItems,
                      ),
                      const SizedBox(height: 24),
                    ],
                  ]),
                ),
              ),
            ],
          ),
          if (!isIdle)
            Positioned.fill(
              child: Container(
                color: kBg,
                child: SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) => Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                          child: Row(
                            children: [
                              const ShellHeader(),
                              const Spacer(),
                              if (shellState.showBackButton)
                                IconButton(
                                  onPressed: notifier.goBack,
                                  icon: const Icon(Icons.close_rounded),
                                  tooltip: 'Close',
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ShellStateContent(
                            view: shellState.view,
                            availableHeight: constraints.maxHeight,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

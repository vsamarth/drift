import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/drift_theme.dart';
import '../state/drift_app_state.dart';
import '../state/drift_providers.dart';
import 'widgets/mobile/mobile_identity_card.dart';
import 'widgets/settings_panel.dart';
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
        builder: (context) => const _MobileSettingsPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(driftAppNotifierProvider);
    final notifier = ref.read(driftAppNotifierProvider.notifier);
    final isIdle = state.session is IdleSession;

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
                        isPicking: state.isInspectingSendItems,
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
                              if (state.session is SendDraftSession ||
                                  state.session is ReceiveOfferSession)
                                IconButton(
                                  onPressed: notifier.resetShell,
                                  icon: const Icon(Icons.close_rounded),
                                  tooltip: 'Close',
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ShellStateContent(
                            view: state.shellView,
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

class _MobileSettingsPage extends StatelessWidget {
  const _MobileSettingsPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close',
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Settings',
                    style: driftSans(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: kInk,
                      letterSpacing: -0.35,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: SettingsPanel(
                  availableHeight: MediaQuery.of(context).size.height,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

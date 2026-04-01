import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/drift_theme.dart';
import '../state/drift_providers.dart';
import '../state/drift_app_state.dart';
import 'widgets/mobile/mobile_identity_card.dart';
import 'widgets/mobile/mobile_transfer_view.dart';
import 'widgets/mobile/send_bottom_sheet.dart';
import 'widgets/shell_state_content.dart';

class MobileShell extends ConsumerStatefulWidget {
  const MobileShell({super.key});

  @override
  ConsumerState<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends ConsumerState<MobileShell> {
  @override
  void initState() {
    super.initState();
    _setupShellListeners();
  }

  void _setupShellListeners() {
    ref.listenManual(driftAppNotifierProvider, (previous, next) {
      final wasDraft = previous?.session is SendDraftSession;
      final isDraft = next.session is SendDraftSession;
      if (!wasDraft && isDraft) {
        _showSendBottomSheet();
      } else if (wasDraft && !isDraft) {
        Navigator.of(context).maybePop();
      }

      final wasOffer = previous?.session is ReceiveOfferSession;
      final isOffer = next.session is ReceiveOfferSession;
      if (!wasOffer && isOffer) {
        _showReceiveOfferBottomSheet();
      } else if (wasOffer && !isOffer) {
        Navigator.of(context).maybePop();
      }
    });
  }

  void _showSendBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const SendBottomSheet(),
    ).then((_) {
      final state = ref.read(driftAppNotifierProvider);
      if (state.session is SendDraftSession) {
        ref.read(driftAppNotifierProvider.notifier).resetShell();
      }
    });
  }

  void _showReceiveOfferBottomSheet() {
    final state = ref.read(driftAppNotifierProvider);
    final summary = state.receiveSummary;
    final items = state.receiveItems;
    final notifier = ref.read(driftAppNotifierProvider.notifier);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        decoration: const BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Incoming files',
              style: driftSans(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              '${summary?.senderName ?? 'Someone'} wants to send you ${items.length} ${items.length == 1 ? 'file' : 'files'} (${summary?.totalSize ?? 'unknown size'})',
              style: driftSans(fontSize: 15, color: kMuted, height: 1.4),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      notifier.declineReceiveOffer();
                      Navigator.pop(context);
                    },
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      notifier.acceptReceiveOffer();
                      Navigator.pop(context);
                    },
                    child: const Text('Accept'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildStepCard({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: kInk, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: driftSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: kInk,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: driftSans(fontSize: 14, color: kMuted, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(driftAppNotifierProvider);
    final notifier = ref.read(driftAppNotifierProvider.notifier);
    final isIdle = state.session is IdleSession;
    final isTransferring =
        state.session is SendTransferSession ||
        state.session is ReceiveTransferSession;

    return Scaffold(
      backgroundColor: kBg,
      body: Stack(
        children: [
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverAppBar(
                expandedHeight: 120,
                floating: false,
                pinned: true,
                backgroundColor: kBg,
                elevation: 0,
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(
                    'Drift',
                    style: driftSans(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: kInk,
                    ),
                  ),
                  centerTitle: false,
                  titlePadding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                ),
                actions: [
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.settings_outlined),
                  ),
                  const SizedBox(width: 8),
                ],
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
                    ),
                    const SizedBox(height: 32),
                    if (isIdle) ...[
                      Text(
                        'GETTING STARTED',
                        style: driftSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: kMuted,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildStepCard(
                        icon: Icons.add_rounded,
                        title: 'Send Files',
                        subtitle:
                            'Tap the plus button below to select and send files.',
                      ),
                      const SizedBox(height: 12),
                      _buildStepCard(
                        icon: Icons.pin_rounded,
                        title: 'Receive Files',
                        subtitle:
                            'Enter the 6-digit code above on another device.',
                      ),
                      const SizedBox(height: 120), // Bottom padding for FAB
                    ],
                  ]),
                ),
              ),
            ],
          ),
          if (!isIdle &&
              state.session is! SendDraftSession &&
              state.session is! ReceiveOfferSession)
            Positioned.fill(
              child: Container(
                color: kBg,
                child: SafeArea(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            if (state.showShellBackButton)
                              IconButton(
                                onPressed: notifier.goBack,
                                icon: const Icon(Icons.arrow_back_rounded),
                              ),
                            const Spacer(),
                            if (!isTransferring)
                              IconButton(
                                onPressed: notifier.resetShell,
                                icon: const Icon(Icons.close_rounded),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: isTransferring
                            ? const MobileTransferView()
                            : ShellStateContent(
                                view: state.shellView,
                                availableHeight: MediaQuery.of(
                                  context,
                                ).size.height,
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: isIdle
          ? FloatingActionButton(
              onPressed: notifier.pickSendItems,
              backgroundColor: kInk,
              foregroundColor: Colors.white,
              child: const Icon(Icons.add_rounded),
            )
          : null,
    );
  }
}

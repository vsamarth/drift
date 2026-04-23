import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/receive/application/controller.dart';
import '../features/receive/presentation/receive_transfer_route_gate.dart';
import '../features/send/presentation/send_selection_source_sheet.dart';
import '../app/app_router.dart';
import '../theme/drift_theme.dart';
import 'widgets/mobile_identity_card.dart';
import 'widgets/select_files_card.dart';
import 'widgets/shell_picking_actions.dart';

class MobileShell extends ConsumerWidget with ShellPickingActions {
  const MobileShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receiverState = ref.watch(receiverIdleViewStateProvider);

    return ReceiveTransferRouteGate(
      child: Scaffold(
        backgroundColor: kBg,
        body: CustomScrollView(
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
                        onPressed: () => context.goSettings(),
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
                  MobileIdentityCard(state: receiverState),
                  const SizedBox(height: 32),
                  SelectFilesCard(
                    onTap: () {
                      showSendSelectionSourceSheet(
                        context,
                        onChooseFiles: () => pickFiles(context, ref),
                        onChooseFolder: () => pickFolder(context, ref),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

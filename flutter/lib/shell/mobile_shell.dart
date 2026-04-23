import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/receive/application/controller.dart';
import '../features/receive/presentation/receive_transfer_route_gate.dart';
import '../features/send/presentation/send_selection_source_sheet.dart';
import '../app/app_router.dart';
import '../theme/drift_theme.dart';
import 'widgets/ambient_background.dart';
import 'widgets/identity_header.dart';
import 'widgets/hero_code.dart';
import 'widgets/integrated_send_button.dart';
import 'widgets/shell_picking_actions.dart';

class MobileShell extends ConsumerWidget with ShellPickingActions {
  const MobileShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receiverState = ref.watch(receiverIdleViewStateProvider);

    return ReceiveTransferRouteGate(
      child: Scaffold(
        backgroundColor: kBg,
        body: Stack(
          children: [
            const AmbientBackground(),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: IdentityHeader(
                      state: receiverState,
                      onOpenSettings: () => context.goSettings(),
                    ),
                  ),
                  const Spacer(),
                  HeroCode(
                    code: receiverState.code,
                    clipboardCode: receiverState.clipboardCode,
                  ),
                  const Spacer(),
                  IntegratedSendButton(
                    onPressed: () {
                      showSendSelectionSourceSheet(
                        context,
                        onChooseFiles: () => pickFiles(context, ref),
                        onChooseFolder: () => pickFolder(context, ref),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

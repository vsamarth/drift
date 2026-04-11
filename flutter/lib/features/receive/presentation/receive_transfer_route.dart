import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_router.dart';
import '../../transfers/application/controller.dart';
import '../../transfers/application/state.dart';
import '../../transfers/application/service.dart';
import '../../../theme/drift_theme.dart';
import '../../transfers/presentation/view.dart';

class ReceiveTransferRoutePage extends ConsumerStatefulWidget {
  const ReceiveTransferRoutePage({super.key});

  @override
  ConsumerState<ReceiveTransferRoutePage> createState() =>
      _ReceiveTransferRoutePageState();
}

class _ReceiveTransferRoutePageState
    extends ConsumerState<ReceiveTransferRoutePage> {
  bool _allowPop = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(transfersViewStateProvider);
    final controller = ref.read(transfersServiceProvider.notifier);

    ref.listen<TransferSessionState>(transfersViewStateProvider, (
      previous,
      next,
    ) {
      if (previous?.phase == next.phase) {
        return;
      }

      if (next.phase != TransferSessionPhase.idle) {
        return;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _allowPop = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        } else {
          context.goHome();
        }
      });
    });

    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          return;
        }

        switch (state.phase) {
          case TransferSessionPhase.offerPending:
            controller.declineOffer();
          case TransferSessionPhase.receiving:
            controller.cancelTransfer();
          case TransferSessionPhase.completed:
          case TransferSessionPhase.cancelled:
          case TransferSessionPhase.failed:
            controller.dismissTransferResult();
          case TransferSessionPhase.idle:
            context.goHome();
        }
      },
      child: Scaffold(
        backgroundColor: kBg,
        body: SafeArea(child: SizedBox.expand(child: const TransfersFeature())),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_router.dart';
import '../../transfers/application/controller.dart';
import '../../transfers/application/state.dart';

class ReceiveTransferRouteGate extends ConsumerStatefulWidget {
  const ReceiveTransferRouteGate({
    super.key,
    required this.child,
    this.onOpenTransfer,
  });

  final Widget child;
  final VoidCallback? onOpenTransfer;

  @override
  ConsumerState<ReceiveTransferRouteGate> createState() =>
      _ReceiveTransferRouteGateState();
}

class _ReceiveTransferRouteGateState
    extends ConsumerState<ReceiveTransferRouteGate> {
  bool _transferRouteActive = false;

  @override
  Widget build(BuildContext context) {
    final transferState = ref.watch(transfersViewStateProvider);

    if (transferState.phase == TransferSessionPhase.idle) {
      _transferRouteActive = false;
    } else if (!_transferRouteActive) {
      _transferRouteActive = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        if (ref.read(transfersViewStateProvider).phase ==
            TransferSessionPhase.idle) {
          _transferRouteActive = false;
          return;
        }
        final openTransfer =
            widget.onOpenTransfer ?? context.pushReceiveTransfer;
        openTransfer();
      });
    }

    return widget.child;
  }
}

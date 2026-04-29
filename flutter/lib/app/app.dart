import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/receive/application/service.dart';
import '../features/receive/presentation/receive_transfer_route_gate.dart';
import 'app_router.dart';
import '../platform/desktop/desktop_lifecycle.dart';
import '../theme/drift_theme.dart';
import '../platform/rust/receiver/source.dart';

class DriftApp extends ConsumerStatefulWidget {
  const DriftApp({super.key});

  @override
  ConsumerState<DriftApp> createState() => _DriftAppState();
}

class _DriftAppState extends ConsumerState<DriftApp> {
  late final GoRouter _router;
  late final ReceiverServiceSource _receiverService;
  bool _discoverableEnabled = false;

  @override
  void initState() {
    super.initState();
    _router = buildAppRouter();
    _receiverService = ref.read(receiverServiceSourceProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _setReceiverDiscovery(enabled: true);
      }
    });
  }

  void _setReceiverDiscovery({required bool enabled}) {
    if (enabled == _discoverableEnabled) {
      return;
    }
    _discoverableEnabled = enabled;
    debugPrint(
      '[app] receiver discovery ${enabled ? 'enabled' : 'disabled'} '
      'while app is running',
    );
    unawaited(_receiverService.setDiscoverable(enabled: enabled));
  }

  void _openReceiveTransfer() {
    unawaited(showDriftWindow());
    final path = _router.routeInformationProvider.value.uri.path;
    if (path == AppRoutePaths.receiveTransfer) {
      return;
    }
    unawaited(_router.push(AppRoutePaths.receiveTransfer));
  }

  @override
  void dispose() {
    _setReceiverDiscovery(enabled: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DesktopLifecycle(
      child: ReceiveTransferRouteGate(
        onOpenTransfer: _openReceiveTransfer,
        child: MaterialApp.router(
          title: 'Drift',
          debugShowCheckedModeBanner: false,
          theme: buildDriftTheme(),
          routerConfig: _router,
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/receive/application/service.dart';
import 'app_router.dart';
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
    _router = buildAppRouter(
      observers: [DiscoveryRouterObserver(_syncReceiverDiscovery)],
    );
    _receiverService = ref.read(receiverServiceSourceProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _syncReceiverDiscovery();
      }
    });
  }

  void _syncReceiverDiscovery() {
    final routePath = _router.routeInformationProvider.value.uri.path;
    final enabled = routePath == AppRoutePaths.home;
    if (enabled == _discoverableEnabled) {
      return;
    }
    _discoverableEnabled = enabled;
    debugPrint(
      '[app] receiver discovery ${enabled ? 'enabled' : 'disabled'} '
      'route="$routePath"',
    );
    unawaited(
      _receiverService.setDiscoverable(enabled: enabled),
    );
  }

  @override
  void dispose() {
    unawaited(
      _receiverService.setDiscoverable(enabled: false),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Drift',
      debugShowCheckedModeBanner: false,
      theme: buildDriftTheme(),
      routerConfig: _router,
    );
  }
}

class DiscoveryRouterObserver extends NavigatorObserver {
  DiscoveryRouterObserver(this._sync);

  final VoidCallback _sync;

  void _scheduleSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _scheduleSync();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _scheduleSync();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _scheduleSync();
  }

  @override
  void didReplace({
    Route<dynamic>? newRoute,
    Route<dynamic>? oldRoute,
  }) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _scheduleSync();
  }
}

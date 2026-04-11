import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../features/send/application/model.dart';
import '../features/send/presentation/send_draft_preview.dart';
import '../features/send/presentation/send_transfer_route.dart';
import '../features/settings/feature.dart';
import '../shell/drift_shell.dart';

abstract final class AppRoutePaths {
  static const String home = '/';
  static const String settings = '/settings';
  static const String sendDraft = '/send/draft';
  static const String sendTransfer = '/send/transfer';

  // GoRouter child routes use relative paths.
  static const String settingsSegment = 'settings';
  static const String sendDraftSegment = 'send/draft';
  static const String sendTransferSegment = 'send/transfer';
}

extension AppRouteNavigation on BuildContext {
  void goHome() => go(AppRoutePaths.home);

  void goSettings() => go(AppRoutePaths.settings);

  void goSendDraft({required List<SendPickedFile> files}) =>
      go(AppRoutePaths.sendDraft, extra: files);

  void pushSendTransfer({required SendRequestData request}) =>
      push(AppRoutePaths.sendTransfer, extra: request);
}

GoRouter buildAppRouter({List<NavigatorObserver> observers = const []}) {
  return GoRouter(
    observers: observers,
    routes: [
      GoRoute(
        path: AppRoutePaths.home,
        builder: (context, state) => const DriftShell(),
        routes: [
          GoRoute(
            path: AppRoutePaths.settingsSegment,
            builder: (context, state) => const SettingsFeature(),
          ),
          GoRoute(
            path: AppRoutePaths.sendDraftSegment,
            builder: (context, state) {
              final files = state.extra as List<SendPickedFile>? ?? const [];
              return SendDraftRoutePage(files: files);
            },
          ),
          GoRoute(
            path: AppRoutePaths.sendTransferSegment,
            builder: (context, state) {
              final request = state.extra as SendRequestData;
              return SendTransferRoutePage(request: request);
            },
          ),
        ],
      ),
    ],
  );
}

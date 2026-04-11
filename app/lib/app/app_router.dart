import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../features/send/application/model.dart';
import '../features/send/presentation/send_draft_preview.dart';
import '../features/settings/feature.dart';
import '../shell/drift_shell.dart';

abstract final class AppRoutePaths {
  static const String home = '/';
  static const String settings = '/settings';
  static const String sendDraft = '/send/draft';

  // GoRouter child routes use relative paths.
  static const String settingsSegment = 'settings';
  static const String sendDraftSegment = 'send/draft';
}

extension AppRouteNavigation on BuildContext {
  void goHome() => go(AppRoutePaths.home);

  void goSettings() => go(AppRoutePaths.settings);

  void goSendDraft({required List<SendPickedFile> files}) =>
      go(AppRoutePaths.sendDraft, extra: files);
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
              return SendDraftPreview(files: files);
            },
          ),
        ],
      ),
    ],
  );
}

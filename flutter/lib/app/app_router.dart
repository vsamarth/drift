import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../features/send/application/model.dart';
import '../features/send/presentation/send_draft_preview.dart';
import '../features/send/presentation/send_transfer_route.dart';
import '../features/receive/presentation/receive_transfer_route.dart';
import '../features/settings/feature.dart';
import '../shell/responsive_shell.dart';
import '../shell/title_bar_shell.dart';

abstract final class AppRoutePaths {
  static const String home = '/';
  static const String settings = '/settings';
  static const String sendDraft = '/send/draft';
  static const String sendTransfer = '/send/transfer';
  static const String receiveTransfer = '/receive/transfer';

  // GoRouter child routes use relative paths.
  static const String settingsSegment = 'settings';
  static const String sendDraftSegment = 'send/draft';
  static const String sendTransferSegment = 'send/transfer';
  static const String receiveTransferSegment = 'receive/transfer';
}

extension AppRouteNavigation on BuildContext {
  void goHome() => go(AppRoutePaths.home);

  void goSettings() => go(AppRoutePaths.settings);

  void goSendDraft({required List<SendPickedFile> files}) =>
      go(AppRoutePaths.sendDraft, extra: files);

  void pushSendTransfer({required SendRequestData request}) =>
      push(AppRoutePaths.sendTransfer, extra: request);

  void pushReceiveTransfer() => push(AppRoutePaths.receiveTransfer);
}

GoRouter buildAppRouter({List<NavigatorObserver> observers = const []}) {
  return GoRouter(
    observers: observers,
    routes: [
      GoRoute(
        path: AppRoutePaths.home,
        builder: (context, state) =>
            const TitleBarShell(child: ResponsiveShell()),
        routes: [
          GoRoute(
            path: AppRoutePaths.settingsSegment,
            builder: (context, state) =>
                const TitleBarShell(child: SettingsFeature()),
          ),
          GoRoute(
            path: AppRoutePaths.sendDraftSegment,
            builder: (context, state) {
              final files = state.extra as List<SendPickedFile>? ?? const [];
              return TitleBarShell(child: SendDraftRoutePage(files: files));
            },
          ),
          GoRoute(
            path: AppRoutePaths.sendTransferSegment,
            builder: (context, state) {
              final extra = state.extra;
              if (extra is SendRequestData) {
                return TitleBarShell(
                  child: SendTransferRoutePage(request: extra),
                );
              }

              return const TitleBarShell(child: SendDraftRoutePage(files: []));
            },
          ),
        ],
      ),
      GoRoute(
        path: AppRoutePaths.receiveTransfer,
        builder: (context, state) =>
            const TitleBarShell(child: ReceiveTransferRoutePage()),
      ),
    ],
  );
}

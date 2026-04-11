import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../features/send/application/model.dart';
import '../features/send/presentation/send_draft_preview.dart';
import '../features/settings/feature.dart';
import '../shell/drift_shell.dart';

GoRouter buildAppRouter() {
  return GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const DriftShell(),
        routes: [
          GoRoute(
            path: 'settings',
            builder: (context, state) => const SettingsFeature(),
          ),
          GoRoute(
            path: 'send/draft',
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


import 'package:app/app/app.dart';
import 'package:app/app/app_router.dart';
import 'package:app/features/settings/settings_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/settings_test_overrides.dart';

void main() {
  test('router exposes the home, settings, and send draft routes', () {
    final router = buildAppRouter();

    expect(router.routeInformationParser, isNotNull);
    expect(router.routerDelegate, isNotNull);
  });

  test('router configuration stays consistent', () {
    final router = buildAppRouter();

    expect(router.configuration.routes, hasLength(1));

    final root = router.configuration.routes.single as GoRoute;
    expect(root.path, AppRoutePaths.home);

    final childPaths = root.routes.cast<GoRoute>().map((r) => r.path).toList();
    expect(childPaths, containsAll(<String>[
      AppRoutePaths.settingsSegment,
      AppRoutePaths.sendDraftSegment,
    ]));
  });

  testWidgets('app starts on the home route', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAppSettingsProvider.overrideWithValue(testAppSettings),
        ],
        child: const DriftApp(),
      ),
    );

    expect(find.text('Drop files to send'), findsOneWidget);
  });
}

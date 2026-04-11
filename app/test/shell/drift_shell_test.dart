import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/app/app_router.dart';
import 'package:app/features/settings/feature.dart';
import 'package:app/features/send/presentation/send_draft_preview.dart';
import 'package:app/features/send/send_drop_zone.dart';
import 'package:app/shell/drift_shell.dart';
import '../support/settings_test_overrides.dart';

void main() {
  testWidgets('shows the receiver card above the send dropzone', (
    WidgetTester tester,
  ) async {
    final router = buildAppRouter();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAppSettingsProvider.overrideWithValue(testAppSettings),
        ],
        child: MaterialApp.router(
          routerConfig: router,
        ),
      ),
    );

    expect(find.text('Drift'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Receive code'), findsOneWidget);
    expect(find.text('Drop files to send'), findsOneWidget);
    expect(find.text('Select files'), findsOneWidget);
  });

  testWidgets('tapping settings navigates to /settings via the router', (
    WidgetTester tester,
  ) async {
    final router = buildAppRouter();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAppSettingsProvider.overrideWithValue(testAppSettings),
        ],
        child: MaterialApp.router(
          routerConfig: router,
        ),
      ),
    );

    expect(router.routeInformationProvider.value.uri.toString(), '/');

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.toString(), '/settings');
    expect(find.byType(SettingsFeature), findsOneWidget);
    expect(find.text('Settings'), findsWidgets);
  });

  testWidgets('dropping files navigates to /send/draft and shows preview', (
    WidgetTester tester,
  ) async {
    final router = buildAppRouter();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAppSettingsProvider.overrideWithValue(testAppSettings),
        ],
        child: MaterialApp.router(
          routerConfig: router,
        ),
      ),
    );

    expect(router.routeInformationProvider.value.uri.toString(), '/');

    final dropZone = tester.widget<SendDropZone>(find.byType(SendDropZone));
    await tester.runAsync(() async {
      dropZone.onDropPaths(const ['/tmp/report.pdf']);
      await Future<void>.delayed(const Duration(milliseconds: 1));
    });
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.toString(), '/send/draft');
    expect(find.byType(SendDraftPreview), findsOneWidget);
    expect(find.text('report.pdf'), findsOneWidget);
  });
}

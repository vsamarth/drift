import 'dart:async';

import 'package:app/app/app.dart';
import 'package:app/app/app_router.dart';
import 'package:app/features/receive/application/service.dart';
import 'package:app/features/send/application/model.dart';
import 'package:app/features/send/application/send_selection_picker.dart';
import 'package:app/platform/rust/receiver/fake_source.dart';
import 'package:app/features/settings/settings_providers.dart';
import 'package:app/features/send/presentation/send_draft_preview.dart';
import 'package:app/features/send/presentation/send_transfer_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/settings_test_overrides.dart';
import 'support/fake_send_selection_picker.dart';

void main() {
  test('router exposes the home, settings, and send draft routes', () {
    final router = buildAppRouter();

    expect(router.routeInformationParser, isNotNull);
    expect(router.routerDelegate, isNotNull);
  });

  test('router configuration stays consistent', () {
    final router = buildAppRouter();

    final allRoutes = router.configuration.routes.cast<GoRoute>().toList();
    final root = allRoutes.firstWhere(
      (route) => route.path == AppRoutePaths.home,
    );
    expect(root.path, AppRoutePaths.home);

    final childPaths = root.routes.cast<GoRoute>().map((r) => r.path).toList();
    expect(
      childPaths,
      containsAll(<String>[
        AppRoutePaths.settingsSegment,
        AppRoutePaths.sendDraftSegment,
        AppRoutePaths.sendTransferSegment,
      ]),
    );
  });

  testWidgets('send transfer route falls back safely when extra is missing', (
    tester,
  ) async {
    final receiverSource = FakeReceiverServiceSource();
    final router = buildAppRouter();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAppSettingsProvider.overrideWithValue(testAppSettings),
          receiverServiceSourceProvider.overrideWithValue(receiverSource),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    router.go(AppRoutePaths.sendTransfer);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.text('No files selected'), findsOneWidget);
    expect(find.byType(SendTransferRoutePage), findsNothing);
  });

  testWidgets(
    'send transfer route falls back safely when extra has wrong type',
    (tester) async {
      final receiverSource = FakeReceiverServiceSource();
      final router = buildAppRouter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            initialAppSettingsProvider.overrideWithValue(testAppSettings),
            receiverServiceSourceProvider.overrideWithValue(receiverSource),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      router.go(AppRoutePaths.sendTransfer, extra: 'invalid-extra');
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(find.text('No files selected'), findsOneWidget);
      expect(find.byType(SendTransferRoutePage), findsNothing);
    },
  );

  testWidgets('app starts on the home route', (tester) async {
    final receiverSource = FakeReceiverServiceSource();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAppSettingsProvider.overrideWithValue(testAppSettings),
          receiverServiceSourceProvider.overrideWithValue(receiverSource),
          sendSelectionPickerProvider.overrideWithValue(
            FakeSendSelectionPicker(
              filesResult: [
                SendPickedFile(
                  path: '/tmp/report.pdf',
                  name: 'report.pdf',
                  sizeBytes: BigInt.from(1024),
                ),
              ],
            ),
          ),
        ],
        child: const DriftApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Drop files to send'), findsOneWidget);
    expect(receiverSource.lastDiscoverableEnabled, isTrue);
    expect(receiverSource.setDiscoverableCalls, 1);
  });

  testWidgets('receiver discovery turns off for settings and back on home', (
    tester,
  ) async {
    final receiverSource = FakeReceiverServiceSource();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAppSettingsProvider.overrideWithValue(testAppSettings),
          receiverServiceSourceProvider.overrideWithValue(receiverSource),
        ],
        child: const DriftApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(receiverSource.lastDiscoverableEnabled, isTrue);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsWidgets);
    expect(receiverSource.lastDiscoverableEnabled, isFalse);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Drop files to send'), findsOneWidget);
    expect(receiverSource.lastDiscoverableEnabled, isTrue);
  });

  testWidgets('receiver discovery turns off while send draft is open', (
    tester,
  ) async {
    final receiverSource = FakeReceiverServiceSource();
    late final GoRouter router;
    final discoveryObserver = DiscoveryRouterObserver(() {
      final uri = router.routeInformationProvider.value.uri;
      final enabled = uri.path == AppRoutePaths.home;
      unawaited(receiverSource.setDiscoverable(enabled: enabled));
    });
    router = buildAppRouter(observers: [discoveryObserver]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAppSettingsProvider.overrideWithValue(testAppSettings),
          receiverServiceSourceProvider.overrideWithValue(receiverSource),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(receiverSource.lastDiscoverableEnabled, isTrue);

    router.go(
      AppRoutePaths.sendDraft,
      extra: [
        SendPickedFile(
          path: '/tmp/report.pdf',
          name: 'report.pdf',
          sizeBytes: BigInt.from(1024),
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.byType(SendDraftPreview), findsOneWidget);
    expect(receiverSource.lastDiscoverableEnabled, isFalse);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Drop files to send'), findsOneWidget);
    expect(receiverSource.lastDiscoverableEnabled, isTrue);
  });
}

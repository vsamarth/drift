import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:app/app/app_router.dart';
import 'package:app/features/receive/feature.dart';
import 'package:app/features/settings/feature.dart';
import 'package:app/features/transfers/feature.dart';
import 'package:app/platform/rust/receiver/fake_source.dart';
import '../../support/settings_test_overrides.dart';

GoRouter _buildReceiveFeatureRouter({required Size size}) {
  return GoRouter(
    initialLocation: AppRoutePaths.home,
    routes: [
      GoRoute(
        path: AppRoutePaths.home,
        builder: (context, state) => Scaffold(
          body: SizedBox(
            width: size.width,
            height: size.height,
            child: const ReceiveFeature(),
          ),
        ),
      ),
      GoRoute(
        path: AppRoutePaths.receiveTransfer,
        builder: (context, state) => const ReceiveTransferRoutePage(),
      ),
    ],
  );
}

void main() {
  testWidgets('shows the receiver idle state', (WidgetTester tester) async {
    final router = _buildReceiveFeatureRouter(size: const Size(440, 260));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transferReviewAnimationProvider.overrideWithValue(false),
          initialAppSettingsProvider.overrideWithValue(testAppSettings),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    expect(find.text('Drift'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Receive code'), findsOneWidget);
    expect(find.text('ABC 123'), findsOneWidget);
    expect(find.text('No offers yet'), findsNothing);
  });

  testWidgets('shows an incoming offer sender', (WidgetTester tester) async {
    final source = FakeReceiverServiceSource();
    final router = _buildReceiveFeatureRouter(size: const Size(440, 560));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transferReviewAnimationProvider.overrideWithValue(false),
          initialAppSettingsProvider.overrideWithValue(testAppSettings),
          receiverServiceSourceProvider.overrideWithValue(source),
          transfersServiceSourceProvider.overrideWithValue(source),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();

    source.emitIncomingOffer(senderName: 'Maya');
    await tester.pumpAndSettle();

    expect(find.text('INCOMING'), findsOneWidget);
    expect(find.text('Maya'), findsAtLeastNWidgets(1));
    expect(find.text('Save to Downloads'), findsOneWidget);
  });

  testWidgets('shows the saved device name on the idle receiver card', (
    WidgetTester tester,
  ) async {
    final source = FakeReceiverServiceSource();
    final router = _buildReceiveFeatureRouter(size: const Size(440, 560));
    const customSettings = AppSettings(
      deviceName: 'Maya MacBook',
      downloadRoot: '/tmp/Drift',
      discoverableByDefault: true,
      discoveryServerUrl: null,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transferReviewAnimationProvider.overrideWithValue(false),
          initialAppSettingsProvider.overrideWithValue(customSettings),
          receiverServiceSourceProvider.overrideWithValue(source),
          transfersServiceSourceProvider.overrideWithValue(source),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    expect(find.text('Maya MacBook'), findsOneWidget);
    expect(find.text('Receive code'), findsOneWidget);
  });

  testWidgets('routes from idle to the incoming offer page', (
    WidgetTester tester,
  ) async {
    final source = FakeReceiverServiceSource();
    final router = _buildReceiveFeatureRouter(size: const Size(440, 560));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transferReviewAnimationProvider.overrideWithValue(false),
          initialAppSettingsProvider.overrideWithValue(testAppSettings),
          receiverServiceSourceProvider.overrideWithValue(source),
          transfersServiceSourceProvider.overrideWithValue(source),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();

    source.emitIncomingOffer(senderName: 'Maya');
    await tester.pumpAndSettle();

    expect(find.text('INCOMING'), findsOneWidget);
    expect(find.text('Maya'), findsAtLeastNWidgets(1));
  });

  testWidgets('returns to idle after declining an offer', (
    WidgetTester tester,
  ) async {
    final source = FakeReceiverServiceSource();
    final router = _buildReceiveFeatureRouter(size: const Size(440, 560));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transferReviewAnimationProvider.overrideWithValue(false),
          initialAppSettingsProvider.overrideWithValue(testAppSettings),
          receiverServiceSourceProvider.overrideWithValue(source),
          transfersServiceSourceProvider.overrideWithValue(source),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();

    source.emitIncomingOffer(senderName: 'Maya');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Decline'));
    await tester.pumpAndSettle();

    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Receive code'), findsOneWidget);
    expect(find.text('INCOMING'), findsNothing);
  });

  testWidgets('opens settings from the idle gear button', (
    WidgetTester tester,
  ) async {
    final router = _buildReceiveFeatureRouter(size: const Size(440, 560));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transferReviewAnimationProvider.overrideWithValue(false),
          initialAppSettingsProvider.overrideWithValue(testAppSettings),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Device name'), findsOneWidget);
  });
}

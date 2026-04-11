import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/receive/feature.dart';
import 'package:app/features/settings/feature.dart';
import 'package:app/platform/rust/receiver/fake_source.dart';
import 'package:app/features/transfers/feature.dart';
import '../../support/settings_test_overrides.dart';

void main() {
  testWidgets('shows the receiver idle state', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transferReviewAnimationProvider.overrideWithValue(false),
          initialAppSettingsProvider.overrideWithValue(testAppSettings),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 440,
              height: 260,
              child: ReceiveFeature(),
            ),
          ),
        ),
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

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transferReviewAnimationProvider.overrideWithValue(false),
          initialAppSettingsProvider.overrideWithValue(testAppSettings),
          receiverServiceSourceProvider.overrideWithValue(source),
          transfersServiceSourceProvider.overrideWithValue(source),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 440,
              height: 560,
              child: ReceiveFeature(),
            ),
          ),
        ),
      ),
    );

    source.emitIncomingOffer(senderName: 'Maya');
    await tester.pumpAndSettle();

    expect(find.text('Ready'), findsNothing);
    expect(find.text('Receive code'), findsNothing);
    expect(find.text('Incoming'), findsOneWidget);
    expect(find.text('Maya'), findsAtLeastNWidgets(1));
  });

  testWidgets('uses the saved device name in the transfer animation', (
    WidgetTester tester,
  ) async {
    final source = FakeReceiverServiceSource();
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
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 440,
              height: 560,
              child: ReceiveFeature(),
            ),
          ),
        ),
      ),
    );

    source.emitIncomingOffer(senderName: 'Maya');
    await tester.pumpAndSettle();

    expect(find.text('Maya MacBook'), findsAtLeastNWidgets(1));
    expect(find.text('Drift'), findsNothing);
  });

  testWidgets('animates from idle to incoming offer', (WidgetTester tester) async {
    final source = FakeReceiverServiceSource();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transferReviewAnimationProvider.overrideWithValue(false),
          initialAppSettingsProvider.overrideWithValue(testAppSettings),
          receiverServiceSourceProvider.overrideWithValue(source),
          transfersServiceSourceProvider.overrideWithValue(source),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 440,
              height: 560,
              child: ReceiveFeature(),
            ),
          ),
        ),
      ),
    );

    source.emitIncomingOffer(senderName: 'Maya');
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('Drift'), findsAtLeastNWidgets(1));
    expect(find.text('Receive code'), findsOneWidget);
    expect(find.text('Maya'), findsAtLeastNWidgets(1));
  });

  testWidgets('returns to idle after declining an offer', (WidgetTester tester) async {
    final source = FakeReceiverServiceSource();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transferReviewAnimationProvider.overrideWithValue(false),
          initialAppSettingsProvider.overrideWithValue(testAppSettings),
          receiverServiceSourceProvider.overrideWithValue(source),
          transfersServiceSourceProvider.overrideWithValue(source),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 440,
              height: 560,
              child: ReceiveFeature(),
            ),
          ),
        ),
      ),
    );

    source.emitIncomingOffer(senderName: 'Maya');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Decline'));
    await tester.pumpAndSettle();

    expect(find.text('Drift'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Receive code'), findsOneWidget);
    expect(find.text('No offers yet'), findsNothing);
    expect(find.text('Incoming offer'), findsNothing);
  });

  testWidgets('opens settings from the idle gear button', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transferReviewAnimationProvider.overrideWithValue(false),
          initialAppSettingsProvider.overrideWithValue(testAppSettings),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 440,
              height: 560,
              child: ReceiveFeature(),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Device name'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/receive/feature.dart';
import 'package:app/features/transfers/feature.dart';
import 'package:app/platform/rust/receiver/fake_source.dart';

void main() {
  testWidgets('shows the empty transfer state', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [transferReviewAnimationProvider.overrideWithValue(false)],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 440, height: 560, child: ReceiveFeature()),
          ),
        ),
      ),
    );

    expect(find.text('No offers yet'), findsOneWidget);
  });

  testWidgets('shows an incoming transfer offer', (WidgetTester tester) async {
    final source = FakeReceiverServiceSource();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transferReviewAnimationProvider.overrideWithValue(false),
          receiverServiceSourceProvider.overrideWithValue(source),
          transfersServiceSourceProvider.overrideWithValue(source),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 440, height: 560, child: ReceiveFeature()),
          ),
        ),
      ),
    );

    source.emitIncomingOffer(senderName: 'Maya');
    await tester.pumpAndSettle();

    expect(find.text('Incoming'), findsOneWidget);
    expect(find.text('Maya'), findsAtLeastNWidgets(1));
    expect(
      find.text('Review the files and accept only if you trust the sender.'),
      findsOneWidget,
    );
    expect(find.text('No offers yet'), findsNothing);
  });

  testWidgets('shows offer details and manifest items', (
    WidgetTester tester,
  ) async {
    final source = FakeReceiverServiceSource();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transferReviewAnimationProvider.overrideWithValue(false),
          receiverServiceSourceProvider.overrideWithValue(source),
          transfersServiceSourceProvider.overrideWithValue(source),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 440, height: 560, child: ReceiveFeature()),
          ),
        ),
      ),
    );

    source.emitIncomingOffer(senderName: 'Maya');
    await tester.pumpAndSettle();

    expect(find.text('Incoming'), findsOneWidget);
    expect(find.text('wants to send you 2 files (3.0 KB).'), findsOneWidget);
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Size'), findsOneWidget);
    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('photo.jpg'), findsOneWidget);
    expect(find.text('Save to Downloads'), findsOneWidget);
  });

  testWidgets('decline button calls the source and returns to idle', (
    tester,
  ) async {
    final source = FakeReceiverServiceSource();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transferReviewAnimationProvider.overrideWithValue(false),
          receiverServiceSourceProvider.overrideWithValue(source),
          transfersServiceSourceProvider.overrideWithValue(source),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 440, height: 560, child: ReceiveFeature()),
          ),
        ),
      ),
    );

    source.emitIncomingOffer(senderName: 'Maya');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Decline'));
    await tester.pumpAndSettle();
    expect(source.lastRespondToOfferAccept, isFalse);
    expect(find.text('Incoming'), findsNothing);
    expect(find.text('No offers yet'), findsOneWidget);
  });

  testWidgets('accepting an offer shows the receiving state', (tester) async {
    final source = FakeReceiverServiceSource();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transferReviewAnimationProvider.overrideWithValue(false),
          receiverServiceSourceProvider.overrideWithValue(source),
          transfersServiceSourceProvider.overrideWithValue(source),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 440, height: 560, child: ReceiveFeature()),
          ),
        ),
      ),
    );

    source.emitIncomingOffer(senderName: 'Maya');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save to Downloads'));
    await tester.pumpAndSettle();

    expect(find.text('Receiving'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Incoming'), findsNothing);
    expect(find.text('wants to send you 2 files (3.0 KB).'), findsNothing);
  });

  testWidgets('cancelling a receiving transfer returns to idle', (
    tester,
  ) async {
    final source = FakeReceiverServiceSource();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transferReviewAnimationProvider.overrideWithValue(false),
          receiverServiceSourceProvider.overrideWithValue(source),
          transfersServiceSourceProvider.overrideWithValue(source),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 440, height: 560, child: ReceiveFeature()),
          ),
        ),
      ),
    );

    source.emitIncomingOffer(senderName: 'Maya');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save to Downloads'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('No offers yet'), findsOneWidget);
    expect(find.text('Receiving'), findsNothing);
  });
}

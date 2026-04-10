import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/receive/feature.dart';
import 'package:app/features/transfers/feature.dart';
import 'package:app/platform/rust/receiver/fake_source.dart';

void main() {
  testWidgets('shows the empty transfer state', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
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

    expect(find.text('No offers yet'), findsOneWidget);
  });

  testWidgets('shows an incoming transfer offer', (WidgetTester tester) async {
    final source = FakeReceiverServiceSource();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
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
    await tester.pump();

    expect(find.text('Incoming offer'), findsOneWidget);
    expect(find.text('Maya'), findsOneWidget);
    expect(find.text('No offers yet'), findsNothing);
  });

  testWidgets('accept and decline buttons call the source', (tester) async {
    final source = FakeReceiverServiceSource();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
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
    await tester.pump();

    await tester.tap(find.text('Accept'));
    await tester.pump();
    expect(source.lastRespondToOfferAccept, isTrue);
    expect(find.text('Incoming offer'), findsOneWidget);

    await tester.tap(find.text('Decline'));
    await tester.pump();
    expect(source.lastRespondToOfferAccept, isFalse);
    expect(find.text('Incoming offer'), findsNothing);
    expect(find.text('No offers yet'), findsOneWidget);
  });
}

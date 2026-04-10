import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/receive/feature.dart';

void main() {
  testWidgets('shows the receiver idle state', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
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
    expect(find.text('No offers yet'), findsOneWidget);
  });
}

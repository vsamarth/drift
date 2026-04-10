import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/receive/receive_feature.dart';

void main() {
  testWidgets('renders the receive placeholder', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 440,
              height: 260,
              child: ReceiveFeaturePlaceholder(),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Receiver'), findsOneWidget);
  });
}

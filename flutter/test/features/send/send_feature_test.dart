import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/send/send_feature.dart';

void main() {
  testWidgets('renders the send placeholder', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 440,
              height: 260,
              child: SendFeaturePlaceholder(),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Send is idle'), findsOneWidget);
  });
}

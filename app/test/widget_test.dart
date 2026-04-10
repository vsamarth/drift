import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/app/app.dart';

void main() {
  testWidgets('shows the placeholder shell', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(440, 560));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const ProviderScope(child: DriftApp()));
    await tester.pumpAndSettle();

    expect(find.text('Receiver'), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);
  });
}

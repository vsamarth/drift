import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/app/app.dart';
import 'package:app/features/settings/feature.dart';
import 'support/settings_test_overrides.dart';

void main() {
  testWidgets('shows the placeholder shell', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(440, 560));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAppSettingsProvider.overrideWithValue(testAppSettings),
        ],
        child: const DriftApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Select files'), findsOneWidget);
  });
}

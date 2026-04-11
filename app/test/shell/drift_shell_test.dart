import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/settings/feature.dart';
import 'package:app/shell/drift_shell.dart';
import '../support/settings_test_overrides.dart';

void main() {
  testWidgets('shows the receiver card above the send dropzone', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAppSettingsProvider.overrideWithValue(testAppSettings),
        ],
        child: const MaterialApp(
          home: DriftShell(),
        ),
      ),
    );

    expect(find.text('Drift'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Receive code'), findsOneWidget);
    expect(find.text('Drop files to send'), findsOneWidget);
    expect(find.text('Select files'), findsOneWidget);
  });
}

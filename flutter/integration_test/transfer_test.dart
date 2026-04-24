import 'package:app/app/app.dart';
import 'package:app/features/settings/feature.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('launches the Drift shell', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAppSettingsProvider.overrideWithValue(
            AppSettings(
              deviceName: 'Drift',
              downloadRoot: '/tmp/Drift',
              discoverableByDefault: true,
              discoveryServerUrl: null,
            ),
          ),
        ],
        child: DriftApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Drop files to send'), findsOneWidget);
  });
}

import 'package:drift_app/features/settings/widgets/settings_panel.dart';
import 'package:drift_app/platform/storage_access_source.dart';
import 'package:drift_app/state/app_identity.dart';
import 'package:drift_app/state/drift_dependencies.dart';
import 'package:drift_app/state/settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeStorageAccessSource extends StorageAccessSource {
  const _FakeStorageAccessSource();

  @override
  Future<String?> pickDirectory({String? initialDirectory}) async {
    return '/Users/test/Downloads/Drift';
  }
}

Widget _buildPanel() {
  return ProviderScope(
    overrides: [
      driftSettingsStoreProvider.overrideWith(
        (ref) => DriftSettingsStore.inMemory(),
      ),
      initialDriftAppIdentityProvider.overrideWith(
        (ref) => const DriftAppIdentity(
          deviceName: 'Drift Device',
          deviceType: 'laptop',
          downloadRoot: '/tmp/Downloads',
          discoverableByDefault: true,
          serverUrl: 'https://drift.samarthv.com',
        ),
      ),
      storageAccessSourceProvider.overrideWith(
        (ref) => const _FakeStorageAccessSource(),
      ),
    ],
    child: const MaterialApp(
      home: Scaffold(body: SettingsPanel(availableHeight: 720)),
    ),
  );
}

void main() {
  testWidgets('settings panel saves edited values', (tester) async {
    await tester.pumpWidget(_buildPanel());

    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Alex\'s MacBook',
      ),
      'My MacBook',
    );
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(find.text('Save Changes'), findsOneWidget);
    expect(find.text('My MacBook'), findsOneWidget);
  });
}

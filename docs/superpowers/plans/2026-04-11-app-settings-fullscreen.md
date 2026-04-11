# App Settings Full-Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a new full-screen settings feature in `app` that seeds first-run defaults, persists them with `shared_preferences`, and opens from the receive idle settings button.

**Architecture:** Keep settings as one shared feature slice with a persisted settings record, a lightweight controller, and a full-screen page that owns its own form editing and dirty-state warning. Load or create the settings record before `runApp`, seed the receiver bridge from that record, and read the saved device name back into the receive idle UI so the app and the settings page share one source of truth.

**Tech Stack:** Flutter, Riverpod, `shared_preferences`, `path_provider`, the existing Rust bridge, and the app theme tokens already in `app/lib/theme/drift_theme.dart`.

---

## File Map

- Create: `app/lib/features/settings/feature.dart` - public feature export.
- Create: `app/lib/features/settings/application/state.dart` - persisted settings record and controller state.
- Create: `app/lib/features/settings/application/repository.dart` - SharedPreferences-backed load/save logic and first-run defaults.
- Create: `app/lib/features/settings/application/controller.dart` - Riverpod controller for the persisted settings state.
- Create: `app/lib/features/settings/settings_providers.dart` - repository/controller providers and bootstrap providers.
- Create: `app/lib/features/settings/presentation/view.dart` - page entry widget used by navigation.
- Create: `app/lib/features/settings/presentation/widgets/settings_page.dart` - full-screen settings UI.
- Create: `app/lib/app/app_bootstrap.dart` - startup helper that loads or creates settings before `runApp`.
- Modify: `app/pubspec.yaml` - add `shared_preferences` and `path_provider`.
- Modify: `app/lib/main.dart` - call bootstrap and wire the receiver source to seeded settings.
- Modify: `app/lib/platform/rust/receiver/rust_source.dart` - accept runtime config instead of hard-coded device name and download root.
- Modify: `app/lib/features/receive/application/controller.dart` - stop hard-coding `Drift` and read the saved device name.
- Modify: `app/lib/features/receive/presentation/view.dart` - open the new settings page from the idle gear button.
- Modify: `app/lib/features/receive/presentation/widgets/idle_card.dart` - keep the existing gear button hook and forward the navigation callback cleanly.
- Test: `app/test/features/settings/settings_repository_test.dart`
- Test: `app/test/features/settings/settings_controller_test.dart`
- Test: `app/test/features/settings/settings_page_test.dart`
- Test: `app/test/features/receive/feature_test.dart`
- Test: `app/test/widget_test.dart`

---

### Task 1: Add the persisted settings model and SharedPreferences repository

**Files:**
- Create: `app/lib/features/settings/application/state.dart`
- Create: `app/lib/features/settings/application/repository.dart`
- Create: `app/lib/features/settings/settings_providers.dart`
- Modify: `app/pubspec.yaml`
- Test: `app/test/features/settings/settings_repository_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:app/features/settings/application/repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('loadOrCreate seeds defaults when preferences are empty', () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = SettingsRepository(
      prefs: prefs,
      randomDeviceName: () => 'Rusty Ridge',
      defaultDownloadRoot: '/tmp/Drift',
    );

    final settings = await repo.loadOrCreate();

    expect(settings.deviceName, 'Rusty Ridge');
    expect(settings.downloadRoot, '/tmp/Drift');
    expect(settings.discoverableByDefault, isTrue);
    expect(settings.discoveryServerUrl, isNull);
  });

  test('save persists edits back to preferences', () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = SettingsRepository(
      prefs: prefs,
      randomDeviceName: () => 'Rusty Ridge',
      defaultDownloadRoot: '/tmp/Drift',
    );

    await repo.save(
      const AppSettings(
        deviceName: 'Maya MacBook',
        downloadRoot: '/Users/maya/Downloads',
        discoverableByDefault: false,
        discoveryServerUrl: 'https://example.com',
      ),
    );

    expect(prefs.getString('settings.device_name'), 'Maya MacBook');
    expect(prefs.getString('settings.download_root'), '/Users/maya/Downloads');
    expect(prefs.getBool('settings.discoverable'), isFalse);
    expect(prefs.getString('settings.server_url'), 'https://example.com');
  });
}
```

- [ ] **Step 2: Run the test and verify it fails for the right reason**

Run: `cd app && flutter test test/features/settings/settings_repository_test.dart -r compact`

Expected: fail because `SettingsRepository` and `AppSettings` do not exist yet.

- [ ] **Step 3: Write the minimal implementation**

Create `AppSettings` in `application/state.dart` with the four persisted fields and equality semantics. Implement `SettingsRepository` so it:

```dart
class SettingsRepository {
  SettingsRepository({
    required this.prefs,
    required this.randomDeviceName,
    required this.defaultDownloadRoot,
  });

  final SharedPreferences prefs;
  final String Function() randomDeviceName;
  final String defaultDownloadRoot;

  Future<AppSettings> loadOrCreate() async {
    final existing = _read();
    if (existing != null) {
      return existing;
    }
    final seeded = AppSettings(
      deviceName: randomDeviceName(),
      downloadRoot: defaultDownloadRoot,
      discoverableByDefault: true,
      discoveryServerUrl: null,
    );
    await save(seeded);
    return seeded;
  }

  Future<void> save(AppSettings settings) async { ... }
}
```

Use the same preference keys already implied by the app’s existing settings naming scheme:
`settings.device_name`, `settings.download_root`, `settings.discoverable`, and `settings.server_url`.

Use `path_provider` to resolve the first-run download root helper the same way the Flutter reference does, instead of hard-coding a path. That keeps the default aligned with the app shell and avoids any new sandbox-permission work for this version.

Add `settings_providers.dart` with:

```dart
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  throw UnimplementedError('settingsRepositoryProvider must be overridden at bootstrap');
});

final initialAppSettingsProvider = Provider<AppSettings>((ref) {
  throw UnimplementedError('initialAppSettingsProvider must be overridden at bootstrap');
});
```

- [ ] **Step 4: Run the repository test again**

Run: `cd app && flutter test test/features/settings/settings_repository_test.dart -r compact`

Expected: pass.

- [ ] **Step 5: Keep the change reviewable**

Do not expand the repository beyond load/save/default-seeding in this task. Leave UI and navigation for later tasks.

---

### Task 2: Bootstrap settings before app startup and feed the saved device name into receive

**Files:**
- Create: `app/lib/app/app_bootstrap.dart`
- Modify: `app/lib/main.dart`
- Modify: `app/lib/platform/rust/receiver/rust_source.dart`
- Modify: `app/lib/features/receive/application/controller.dart`
- Modify: `app/lib/features/receive/application/controller.g.dart`
- Test: `app/test/app_bootstrap_test.dart`
- Test: `app/test/widget_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:app/app/app_bootstrap.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('bootstrap creates seeded settings on first launch', () async {
    final bootstrap = await loadAppBootstrap(
      randomDeviceName: () => 'Rusty Ridge',
      defaultDownloadRoot: '/tmp/Drift',
    );

    expect(bootstrap.initialSettings.deviceName, 'Rusty Ridge');
    expect(bootstrap.initialSettings.downloadRoot, '/tmp/Drift');
    expect(bootstrap.initialSettings.discoverableByDefault, isTrue);
    expect(bootstrap.initialSettings.discoveryServerUrl, isNull);
  });
}
```

- [ ] **Step 2: Run the bootstrap test and verify it fails**

Run: `cd app && flutter test test/app_bootstrap_test.dart -r compact`

Expected: fail because `loadAppBootstrap` does not exist yet.

- [ ] **Step 3: Write the minimal bootstrap and wiring**

Create `app/lib/app/app_bootstrap.dart` with a helper that:

```dart
Future<AppBootstrap> loadAppBootstrap({
  String Function()? randomDeviceName,
  String? defaultDownloadRoot,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final repository = SettingsRepository(
    prefs: prefs,
    randomDeviceName: randomDeviceName ?? rustRandomDeviceName,
    defaultDownloadRoot:
        defaultDownloadRoot ?? await resolvePreferredReceiveDownloadRoot(),
  );
  final initialSettings = await repository.loadOrCreate();
  final receiverSource = RustReceiverServiceSource(
    deviceName: initialSettings.deviceName,
    downloadRoot: initialSettings.downloadRoot,
    serverUrl: initialSettings.discoveryServerUrl,
  );
  return AppBootstrap(
    settingsRepository: repository,
    initialSettings: initialSettings,
    receiverSource: receiverSource,
  );
}
```

Update `main.dart` so it awaits bootstrap before `runApp`, then overrides:

```dart
settingsRepositoryProvider.overrideWithValue(bootstrap.settingsRepository)
initialAppSettingsProvider.overrideWithValue(bootstrap.initialSettings)
receiverServiceSourceProvider.overrideWithValue(bootstrap.receiverSource)
transfersServiceSourceProvider.overrideWithValue(bootstrap.receiverSource)
```

Update `rust_source.dart` so `RustReceiverServiceSource` accepts `deviceName`, `downloadRoot`, and `serverUrl` through its constructor instead of hard-coded statics.

Update `receiverIdleViewState` so the displayed device name comes from the saved settings provider rather than the string literal `Drift`.

Regenerate Riverpod output after changing `app/lib/features/receive/application/controller.dart`:

```bash
cd app && flutter pub run build_runner build --delete-conflicting-outputs
```

- [ ] **Step 4: Run the bootstrap and smoke tests**

Run:

```bash
cd app && flutter test test/app_bootstrap_test.dart -r compact
cd app && flutter test test/widget_test.dart -r compact
```

Expected: both pass.

- [ ] **Step 5: Keep runtime wiring narrow**

Only seed the receiver source and receive idle label here. Leave the full settings page and save flow for the next task.

---

### Task 3: Build the full-screen settings page and open it from the receive idle gear button

**Files:**
- Create: `app/lib/features/settings/feature.dart`
- Create: `app/lib/features/settings/presentation/view.dart`
- Create: `app/lib/features/settings/presentation/widgets/settings_page.dart`
- Modify: `app/lib/features/receive/presentation/view.dart`
- Modify: `app/lib/features/receive/presentation/widgets/idle_card.dart`
- Test: `app/test/features/settings/settings_page_test.dart`
- Test: `app/test/features/receive/feature_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:app/features/settings/presentation/view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('settings page renders the full-screen form', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: SettingsPage()),
    );

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Device name'), findsOneWidget);
    expect(find.text('Save received files to'), findsOneWidget);
    expect(find.text('Nearby discoverability'), findsOneWidget);
    expect(find.text('Advanced'), findsOneWidget);
    expect(find.text('Discovery Server'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });
}
```

Add a second navigation test in `app/test/features/receive/feature_test.dart`:

```dart
await tester.tap(find.byKey(const ValueKey<String>('idle-settings-button')));
await tester.pumpAndSettle();
expect(find.text('Settings'), findsOneWidget);
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run:

```bash
cd app && flutter test test/features/settings/settings_page_test.dart -r compact
cd app && flutter test test/features/receive/feature_test.dart -r compact
```

Expected: fail because `SettingsPage` and the navigation hookup do not exist yet.

- [ ] **Step 3: Write the minimal page and navigation**

Create a single `Scaffold`-based full-screen page with:

```dart
SafeArea(
  child: Column(
    children: [
      Row(
        children: [
          BackButton(onPressed: _handleBack),
          Text('Settings'),
        ],
      ),
      Expanded(child: SingleChildScrollView(child: ...form...)),
      _SettingsFooter(saveEnabled: _isDirty, onSave: _saveSettings),
    ],
  ),
)
```

Keep the form lightweight and themed like the Flutter reference:

- bordered white surface on the app background
- one sticky footer with the save button
- the cyan primary button styling for save
- a compact error banner at the top when save fails

In `ReceiveFeature`, pass a callback into `ReceiveIdleCard` that pushes the new page with `Navigator.of(context).push(...)`.

Update `ReceiveIdleCard` so the existing gear button simply invokes the callback and does not own navigation logic itself.

- [ ] **Step 4: Run the page and navigation tests**

Run:

```bash
cd app && flutter test test/features/settings/settings_page_test.dart -r compact
cd app && flutter test test/features/receive/feature_test.dart -r compact
```

Expected: both pass.

- [ ] **Step 5: Keep the page shared**

Do not add separate desktop and mobile settings layouts. The same full-screen page should work for both.

---

### Task 4: Add dirty-state handling, validation, save flow, and unsaved-change warnings

**Files:**
- Modify: `app/lib/features/settings/application/controller.dart`
- Modify: `app/lib/features/settings/presentation/widgets/settings_page.dart`
- Modify: `app/lib/features/settings/application/state.dart`
- Test: `app/test/features/settings/settings_controller_test.dart`
- Test: `app/test/features/settings/settings_page_test.dart`

- [ ] **Step 1: Write the failing tests**

Controller test:

```dart
test('save keeps the page dirty when persistence fails', () async {
  final repo = FakeSettingsRepository(throwsOnSave: true);
  final controller = SettingsController(repository: repo, initialSettings: seed);

  await controller.updateDeviceName('New Name');
  await expectLater(controller.save(), throwsA(isException));

  expect(controller.state.isSaving, isFalse);
  expect(controller.state.errorMessage, isNotNull);
  expect(controller.state.settings.deviceName, 'Original Name');
});
```

Page test:

```dart
testWidgets('back navigation warns about unsaved changes', (tester) async {
  await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
  await tester.enterText(find.byType(TextField).first, 'Edited Name');
  await tester.tap(find.byTooltip('Back'));
  await tester.pumpAndSettle();

  expect(find.text('Discard changes?'), findsOneWidget);
  expect(find.text('Stay'), findsOneWidget);
  expect(find.text('Discard'), findsOneWidget);
});
```

Also add a save-button state assertion:

```dart
expect(find.widgetWithText(FilledButton, 'Save'), findsNothing);
```

until the form is dirty.

- [ ] **Step 2: Run the tests and verify the failures are about missing behavior**

Run:

```bash
cd app && flutter test test/features/settings/settings_controller_test.dart -r compact
cd app && flutter test test/features/settings/settings_page_test.dart -r compact
```

Expected: fail because validation, dirty tracking, and warning handling are not implemented yet.

- [ ] **Step 3: Write the minimal controller and page logic**

Implement `SettingsController` as the owner of the persisted record and save state:

```dart
class SettingsController extends Notifier<SettingsState> {
  late final SettingsRepository _repository;

  @override
  SettingsState build() {
    _repository = ref.watch(settingsRepositoryProvider);
    return SettingsState(settings: ref.watch(initialAppSettingsProvider));
  }

  Future<void> save(AppSettings next) async {
    final normalized = next.copyWith(
      deviceName: next.deviceName.trim(),
      downloadRoot: next.downloadRoot.trim(),
      discoveryServerUrl: next.discoveryServerUrl?.trim().isEmpty == true
          ? null
          : next.discoveryServerUrl?.trim(),
    );
    if (normalized == state.settings) return;

    state = state.copyWith(isSaving: true, clearErrorMessage: true);
    try {
      await _repository.save(normalized);
      state = state.copyWith(settings: normalized, isSaving: false, clearErrorMessage: true);
    } catch (error) {
      state = state.copyWith(isSaving: false, errorMessage: error.toString());
      rethrow;
    }
  }
}
```

Keep dirty tracking inside the page by comparing the form controllers against the loaded settings record. Use `PopScope` or `WillPopScope` to intercept back navigation and show a confirmation dialog before leaving with unsaved changes.

Validation rules in the page:

- device name must not be empty after trimming
- download folder must not be empty after trimming
- discovery server may be blank

The settings page should not clear field values on save failure.

- [ ] **Step 4: Run the controller and page tests again**

Run:

```bash
cd app && flutter test test/features/settings/settings_controller_test.dart -r compact
cd app && flutter test test/features/settings/settings_page_test.dart -r compact
```

Expected: pass.

- [ ] **Step 5: Final sanity pass**

Make sure the page still uses the same shared full-screen layout on desktop and mobile, and that the receive idle button opens the page without additional routing infrastructure.

---

## Self-Review

### Spec Coverage

- Shared preferences persistence and first-run defaults are covered by Task 1.
- Startup bootstrap and runtime seeding of the receiver bridge are covered by Task 2.
- Full-screen page layout and gear-button navigation are covered by Task 3.
- Dirty tracking, validation, save flow, and unsaved-change warnings are covered by Task 4.

### Placeholder Scan

- No TBD or TODO placeholders are left in the plan.
- File paths are specific and match the current `app` tree.

### Type Consistency

- `AppSettings` is the persisted record.
- `SettingsState` is the controller/page state.
- `SettingsRepository` owns SharedPreferences I/O.
- `SettingsController` owns save orchestration.
- `SettingsPage` is the full-screen UI entry point.

### Scope Check

- The plan stays focused on one settings feature with one page, one repository, and one bootstrap path.
- It does not add a second desktop-specific presentation.
- It does not introduce unrelated feature work outside settings and the receive idle entry point.

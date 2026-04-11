# App Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the home-shell's ad hoc route pushes with `go_router` so the home, settings, and send draft preview screens are addressable, consistent, and easy to extend.

**Architecture:** Introduce a single app router that owns the top-level route table and route helpers. Keep the screen widgets themselves mostly unchanged; the refactor should move navigation intent out of the widgets and into route definitions while preserving the current UI and back behavior. The send draft route should accept the selected files through route `extra` data so the same path can reopen a specific preview payload.

**Tech Stack:** Flutter, Riverpod, `go_router`, `file_selector`, widget tests

---

### Task 1: Add the top-level router and wire `MaterialApp.router`

**Files:**
- Create: `app/lib/app/app_router.dart`
- Modify: `app/lib/app/app.dart`
- Modify: `app/pubspec.yaml`
- Modify: `app/pubspec.lock`
- Test: `app/test/app_router_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:app/app/app_router.dart';

void main() {
  test('router exposes the home, settings, and send draft routes', () {
    final router = buildAppRouter();

    expect(router.routeInformationParser, isNotNull);
    expect(router.routerDelegate, isNotNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/app_router_test.dart`
Expected: FAIL because `buildAppRouter()` does not exist yet.

- [ ] **Step 3: Write minimal implementation**

```dart
import 'package:go_router/go_router.dart';
import 'package:flutter/widgets.dart';

import '../features/receive/feature.dart';
import '../features/send/presentation/send_draft_preview.dart';
import '../features/settings/feature.dart';
import '../shell/drift_shell.dart';

GoRouter buildAppRouter() {
  return GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const DriftShell(),
        routes: [
          GoRoute(
            path: 'settings',
            builder: (context, state) => const SettingsFeature(),
          ),
          GoRoute(
            path: 'send/draft',
            builder: (context, state) {
              final files = state.extra as List<SendPickedFile>? ?? const [];
              return SendDraftPreview(files: files);
            },
          ),
        ],
      ),
    ],
  );
}
```

Update `app/lib/app/app.dart` to use:

```dart
return MaterialApp.router(
  title: 'Drift',
  debugShowCheckedModeBanner: false,
  theme: buildDriftTheme(),
  routerConfig: buildAppRouter(),
);
```

Add `go_router` to `app/pubspec.yaml`, then refresh the lockfile with `flutter pub get`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/app_router_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/app/app.dart app/lib/app/app_router.dart app/pubspec.yaml app/pubspec.lock app/test/app_router_test.dart
git commit -m "feat: add app router"
```

### Task 2: Move home-shell navigation onto named routes

**Files:**
- Modify: `app/lib/shell/drift_shell.dart`
- Modify: `app/lib/features/send/presentation/send_draft_preview.dart`
- Modify: `app/lib/features/settings/feature.dart` if route helpers are surfaced there
- Modify: `app/lib/features/send/application/model.dart` only if route arguments need a dedicated type
- Test: `app/test/shell/drift_shell_test.dart`
- Test: `app/test/features/send/presentation/send_draft_preview_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
testWidgets('tapping settings opens the settings route', (tester) async {
  await tester.pumpWidget(
    const ProviderScope(
      child: MaterialApp(
        home: DriftShell(),
      ),
    ),
  );

  await tester.tap(find.byTooltip('Settings'));
  await tester.pumpAndSettle();

  expect(find.text('Settings'), findsWidgets);
});
```

and:

```dart
testWidgets('tapping back on send draft preview returns home', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SendDraftPreview(files: []),
                ),
              );
            },
            child: const Text('Open preview'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Open preview'));
  await tester.pumpAndSettle();

  expect(find.byType(SendDraftPreview), findsOneWidget);

  await tester.tap(find.byTooltip('Back'));
  await tester.pumpAndSettle();

  expect(find.byType(SendDraftPreview), findsNothing);
  expect(find.text('Open preview'), findsOneWidget);
});
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/shell/drift_shell_test.dart test/features/send/presentation/send_draft_preview_test.dart`
Expected: FAIL because navigation still uses direct `Navigator.push` calls and the router has not been wired into the widgets yet.

- [ ] **Step 3: Write minimal implementation**

Replace direct `Navigator.push` calls with `context.go('/settings')` and `context.go('/send/draft', extra: files)`, or equivalent router helpers. Keep the existing screen widgets unchanged.

Use a route-aware back button on `SendDraftPreview`:

```dart
leading: IconButton(
  tooltip: 'Back',
  icon: const Icon(Icons.arrow_back_rounded),
  onPressed: () => context.pop(),
),
```

Ensure the home shell still renders the receiver card plus the drop zone exactly as before, and that the router still receives the selected files payload when the preview opens.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/shell/drift_shell_test.dart test/features/send/presentation/send_draft_preview_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/shell/drift_shell.dart app/lib/features/send/presentation/send_draft_preview.dart app/test/shell/drift_shell_test.dart app/test/features/send/presentation/send_draft_preview_test.dart
git commit -m "feat: route home and preview screens"
```

### Task 3: Add route coverage and clean up legacy push code

**Files:**
- Modify: `app/lib/app/app_router.dart`
- Modify: `app/lib/app/app.dart`
- Modify: `app/lib/shell/drift_shell.dart`
- Test: `app/test/app_router_test.dart`
- Test: `app/test/shell/drift_shell_test.dart`
- Test: `app/test/features/send/presentation/send_draft_preview_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
testWidgets('app starts on the home route', (tester) async {
  await tester.pumpWidget(
    const ProviderScope(
      child: DriftApp(),
    ),
  );

  expect(find.text('Drop files to send'), findsOneWidget);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/app_router_test.dart test/shell/drift_shell_test.dart test/features/send/presentation/send_draft_preview_test.dart`
Expected: FAIL if any remaining direct navigation or missing route setup keeps the route stack inconsistent.

- [ ] **Step 3: Write minimal implementation**

Remove any leftover `Navigator.push` usage from the home shell that is now covered by router navigation. Keep the router table centralized and add any convenience route helpers needed to avoid string duplication. Preserve the `extra` payload handling for the selected files route.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/app_router_test.dart test/shell/drift_shell_test.dart test/features/send/presentation/send_draft_preview_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/app/app_router.dart app/lib/app/app.dart app/lib/shell/drift_shell.dart app/test/app_router_test.dart app/test/shell/drift_shell_test.dart app/test/features/send/presentation/send_draft_preview_test.dart
git commit -m "fix: finalize app routing"
```

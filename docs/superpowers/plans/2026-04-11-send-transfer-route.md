# Send Transfer Route Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the send review screen with a direct transfer page that starts the FRB transfer immediately and shows live progress and result state.

**Architecture:** Keep `SendController` as the owner of send draft state, request validation, and the active transfer subscription. The draft page still handles file selection and destination choice, but `Send` now builds a validated `SendRequestData` and pushes a new transfer route. The transfer route is responsible for showing the request summary and live transfer lifecycle, while delegating the actual FRB start/cancel work back to the controller as soon as the route opens.

**Tech Stack:** Flutter, Riverpod, GoRouter, Flutter Rust Bridge, `flutter_test`

---

### Task 1: Add request snapshot and direct-send validation to the send controller

**Files:**
- Modify: `app/lib/features/send/application/state.dart`
- Modify: `app/lib/features/send/application/controller.dart`
- Test: `app/test/features/send/application/state_test.dart`
- Test: `app/test/features/send/application/controller_test.dart`

- [ ] **Step 1: Write the failing tests**

Add tests that describe the new state shape and request-building behavior:

```dart
test('send state can represent a nearby destination', () {
  const state = SendState.drafting(
    items: [],
    destination: SendDestinationState.nearby(
      ticket: 'ticket-1',
      lanDestinationLabel: 'Laptop',
    ),
  );

  expect(state.destination.mode, SendDestinationMode.nearby);
  expect(state.destination.ticket, 'ticket-1');
  expect(state.destination.lanDestinationLabel, 'Laptop');
});

test('send controller builds a nearby request without prefilled code', () {
  final container = ProviderContainer(
    overrides: [
      initialAppSettingsProvider.overrideWithValue(testAppSettings),
    ],
  );
  addTearDown(container.dispose);

  final controller = container.read(sendControllerProvider.notifier);
  controller.beginDraft([
    SendPickedFile(
      path: '/tmp/report.pdf',
      name: 'report.pdf',
      sizeBytes: BigInt.from(1024),
    ),
  ]);
  controller.selectNearbyReceiver(
    const NearbyReceiver(
      fullname: 'samarth-laptop',
      label: 'Laptop',
      code: 'ABC123',
      ticket: 'ticket-1',
    ),
  );

  final request = controller.buildSendRequest();

  expect(request, isNotNull);
  expect(request?.destinationMode, SendDestinationMode.nearby);
  expect(request?.ticket, 'ticket-1');
  expect(request?.lanDestinationLabel, 'Laptop');
  expect(request?.code, isNull);
  expect(request?.paths, ['/tmp/report.pdf']);
});
```

Also add a test that `canStartSend` is true for a valid code or nearby destination and false when destination is missing.

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
flutter test test/features/send/application/state_test.dart test/features/send/application/controller_test.dart -r expanded
```

Expected: FAIL because the controller still exposes the review-oriented send flow and does not yet start the transfer page directly.

- [ ] **Step 3: Write the minimal implementation**

Keep the existing request snapshot model in `model.dart`, and add the missing direct-send state transitions in `state.dart` and `controller.dart`:

```dart
enum SendSessionPhase { idle, drafting, transferring, result }
```

Update `SendState` so the draft state stores `SendDestinationState` and the state keeps a `request` slot for the transfer page and final result use.

Add controller helpers:

```dart
SendRequestData? buildSendRequest() {
  if (state.phase != SendSessionPhase.drafting || state.items.isEmpty) {
    return null;
  }

  final settings = ref.read(settingsControllerProvider).settings;
  final paths = state.items.map((item) => item.path).toList(growable: false);

  return switch (state.destination.mode) {
    SendDestinationMode.none => null,
    SendDestinationMode.code => {
      final code = _normalizedCode(state.destination.code ?? '');
      if (code.length != 6) null else SendRequestData(
        destinationMode: SendDestinationMode.code,
        paths: paths,
        deviceName: settings.deviceName,
        deviceType: _localDeviceTypeLabel(),
        code: code,
        serverUrl: settings.discoveryServerUrl,
      ),
    },
    SendDestinationMode.nearby => SendRequestData(
      destinationMode: SendDestinationMode.nearby,
      paths: paths,
      deviceName: settings.deviceName,
      deviceType: _localDeviceTypeLabel(),
      ticket: state.destination.ticket,
      lanDestinationLabel: state.destination.lanDestinationLabel,
      serverUrl: settings.discoveryServerUrl,
    ),
  };
}

bool get canStartSend => buildSendRequest() != null;

void startTransfer(SendRequestData request) {
  final transferSource = ref.read(sendTransferSourceProvider);
  state = SendState.transferring(
    items: state.items,
    destination: state.destination,
    request: request,
  );
  unawaited(_transferSubscription?.cancel());
  _transferSubscription = transferSource.startTransfer(
    SendTransferRequestData(
      code: request.code ?? '',
      paths: request.paths,
      deviceName: request.deviceName,
      deviceType: request.deviceType,
      serverUrl: request.serverUrl,
      ticket: request.ticket,
      lanDestinationLabel: request.lanDestinationLabel,
    ),
  ).listen(_handleTransferUpdate, onError: _handleTransferError);
}

void cancelTransfer() {
  unawaited(_cancelActiveTransfer());
  if (state.phase == SendSessionPhase.transferring) {
    state = SendState.drafting(
      items: state.items,
      destination: state.destination,
    );
  }
}
```

Remove `beginReview()` and `cancelReview()` once the transfer route takes over. Keep `updateDestinationCode`, `clearDestinationCode`, and `selectNearbyReceiver` mutually exclusive. Nearby selection should write `SendDestinationState.nearby(...)` and should not prefill the code field.

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
flutter test test/features/send/application/state_test.dart test/features/send/application/controller_test.dart -r expanded
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/send/application/model.dart app/lib/features/send/application/state.dart app/lib/features/send/application/controller.dart app/test/features/send/application/state_test.dart app/test/features/send/application/controller_test.dart
git commit -m "feat: add direct-send request snapshot"
```

---

### Task 2: Add the direct transfer route and start FRB on route entry

**Files:**
- Create: `app/lib/features/send/presentation/send_transfer_route.dart`
- Modify: `app/lib/app/app_router.dart`
- Modify: `app/lib/features/send/application/controller.dart`
- Modify: `app/lib/features/send/presentation/send_draft_preview.dart`
- Delete: `app/lib/features/send/presentation/send_review_route.dart`
- Test: `app/test/features/send/presentation/send_transfer_route_test.dart`

- [ ] **Step 1: Write the failing test**

Create a test that expects the new route to render the request and enter the transferring state immediately:

```dart
testWidgets('send transfer route starts transfer on entry', (
  WidgetTester tester,
) async {
  final container = ProviderContainer(
    overrides: [
      initialAppSettingsProvider.overrideWithValue(testAppSettings),
      sendTransferSourceProvider.overrideWithValue(FakeSendTransferSource()),
    ],
  );
  addTearDown(container.dispose);

  final controller = container.read(sendControllerProvider.notifier);
  controller.beginDraft([
    SendPickedFile(
      path: '/tmp/report.pdf',
      name: 'report.pdf',
      sizeBytes: BigInt.from(1024),
    ),
  ]);
  controller.updateDestinationCode('ABC123');
  final request = controller.buildSendRequest();

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: SendTransferRoutePage(request: request!),
      ),
    ),
  );
  await tester.pump();

  expect(container.read(sendControllerProvider).phase, SendSessionPhase.transferring);
  expect(find.text('ABC123'), findsOneWidget);
  expect(find.text('/tmp/report.pdf'), findsOneWidget);
});
```

Add a second test for back behavior:

```dart
testWidgets('back from transfer route returns to drafting', (
  WidgetTester tester,
) async {
  final fakeSource = FakeSendTransferSource();
  final container = ProviderContainer(
    overrides: [
      initialAppSettingsProvider.overrideWithValue(testAppSettings),
      sendTransferSourceProvider.overrideWithValue(fakeSource),
    ],
  );
  addTearDown(container.dispose);

  final controller = container.read(sendControllerProvider.notifier);
  controller.beginDraft([
    SendPickedFile(
      path: '/tmp/report.pdf',
      name: 'report.pdf',
      sizeBytes: BigInt.from(1024),
    ),
  ]);
  controller.updateDestinationCode('ABC123');
  final request = controller.buildSendRequest()!;

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: SendTransferRoutePage(request: request),
      ),
    ),
  );
  await tester.pump();

  await tester.pageBack();
  await tester.pumpAndSettle();

  expect(fakeSource.cancelCalled, isTrue);
  expect(container.read(sendControllerProvider).phase, SendSessionPhase.drafting);
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
flutter test test/features/send/presentation/send_transfer_route_test.dart -r expanded
```

Expected: FAIL because `SendTransferRoutePage` does not exist and route wiring is missing.

- [ ] **Step 3: Write the minimal implementation**

Create `SendTransferRoutePage` that:
- receives a `SendRequestData`
- renders the request summary read-only
- calls `controller.startTransfer(request)` in `initState`
- watches controller state for `transferring` and `result`
- shows live progress and terminal state
- uses back navigation to call `controller.cancelTransfer()`

Use the existing FRB adapter in `app/lib/platform/send_transfer_source.dart` and keep it as the only bridge to generated Rust code.

Route wiring:

```dart
GoRoute(
  path: AppRoutePaths.sendTransferSegment,
  builder: (context, state) {
    final request = state.extra as SendRequestData;
    return SendTransferRoutePage(request: request);
  },
),
```

Update `AppRoutePaths` and the navigation extension so the app exposes `sendTransfer` / `sendTransferSegment` plus `pushSendTransfer({required SendRequestData request})` instead of the old review route names. Update the draft page so `Send` navigates directly to the transfer route with the built request.

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
flutter test test/features/send/presentation/send_transfer_route_test.dart -r expanded
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/app/app_router.dart app/lib/features/send/presentation/send_transfer_route.dart app/lib/features/send/presentation/send_draft_preview.dart app/lib/features/send/application/controller.dart app/test/features/send/presentation/send_transfer_route_test.dart
git commit -m "feat: add direct send transfer route"
```

---

### Task 3: Rewire the draft page so Send pushes the transfer route

**Files:**
- Modify: `app/lib/features/send/presentation/send_draft_preview.dart`
- Modify: `app/test/features/send/presentation/send_draft_preview_test.dart`

- [ ] **Step 1: Write the failing test**

Add a widget test that proves tapping `Send` navigates straight to the transfer route, without any review route:

```dart
testWidgets('tapping Send opens the transfer route directly', (
  WidgetTester tester,
) async {
  final container = ProviderContainer(
    overrides: [
      initialAppSettingsProvider.overrideWithValue(testAppSettings),
      sendTransferSourceProvider.overrideWithValue(FakeSendTransferSource()),
    ],
  );
  addTearDown(container.dispose);

  final router = buildAppRouter();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );

  container.read(sendControllerProvider.notifier).beginDraft([
    SendPickedFile(
      path: '/tmp/report.pdf',
      name: 'report.pdf',
      sizeBytes: BigInt.from(1024),
    ),
  ]);
  await tester.pump();

  await tester.enterText(find.byType(TextField).first, 'ABC123');
  await tester.tap(find.text('Send'));
  await tester.pumpAndSettle();

  expect(find.text('/tmp/report.pdf'), findsOneWidget);
  expect(find.text('Transferring'), findsOneWidget);
  expect(find.text('Review'), findsNothing);
});
```

Also add a nearby-selection regression:

```dart
testWidgets('selecting nearby does not prefill the code field', (
  WidgetTester tester,
) async {
  final container = ProviderContainer(
    overrides: [
      initialAppSettingsProvider.overrideWithValue(testAppSettings),
      sendTransferSourceProvider.overrideWithValue(FakeSendTransferSource()),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: SendDraftPreview(),
      ),
    ),
  );

  container.read(sendControllerProvider.notifier).beginDraft([
    SendPickedFile(
      path: '/tmp/report.pdf',
      name: 'report.pdf',
      sizeBytes: BigInt.from(1024),
    ),
  ]);
  await tester.pump();

  await tester.tap(find.text('Laptop'));
  await tester.pump();

  expect(container.read(sendControllerProvider).destination.mode, SendDestinationMode.nearby);
  expect(find.byType(TextField), findsOneWidget);
  expect((tester.widget(find.byType(TextField)) as EditableText).controller.text, isEmpty);
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
flutter test test/features/send/presentation/send_draft_preview_test.dart -r expanded
```

Expected: FAIL because the draft page still routes through the old behavior.

- [ ] **Step 3: Write the minimal implementation**

Update the draft page button handler to:

```dart
final request = controller.buildSendRequest();
if (request == null) {
  return;
}
context.pushSendTransfer(request: request);
```

Make the nearby tile write `selectNearbyReceiver(receiver)` instead of pre-filling the code field.

Keep the send button enabled only when `controller.canStartSend` returns true.

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
flutter test test/features/send/presentation/send_draft_preview_test.dart -r expanded
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/send/presentation/send_draft_preview.dart app/test/features/send/presentation/send_draft_preview_test.dart
git commit -m "feat: route send directly to transfer"
```

---

### Task 4: Clean up the send route, result handling, and regression coverage

**Files:**
- Modify: `app/lib/features/send/send_feature.dart`
- Modify: `app/test/features/send/send_feature_test.dart`
- Modify: `app/test/shell/drift_shell_test.dart`
- Modify: `app/test/app_router_test.dart`
- Modify: `app/test/features/send/presentation/send_transfer_route_test.dart`

- [ ] **Step 1: Write the failing tests**

Add or update tests so the feature placeholder and router still reflect the send phases after the transfer route lands:

```dart
testWidgets('send placeholder reflects transferring and result phases', (
  WidgetTester tester,
) async {
  final container = ProviderContainer(
    overrides: [
      initialAppSettingsProvider.overrideWithValue(testAppSettings),
    ],
  );
  addTearDown(container.dispose);

  final controller = container.read(sendControllerProvider.notifier);
  controller.beginDraft([
    SendPickedFile(
      path: '/tmp/report.pdf',
      name: 'report.pdf',
      sizeBytes: BigInt.from(1024),
    ),
  ]);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SendFeaturePlaceholder()),
    ),
  );
  await tester.pump();

  expect(find.text('Drafting'), findsOneWidget);

  controller.selectNearbyReceiver(
    const NearbyReceiver(
      fullname: 'samarth-laptop',
      label: 'Laptop',
      code: 'ABC123',
      ticket: 'ticket-1',
    ),
  );
  controller.startTransfer(controller.buildSendRequest()!);
  await tester.pump();

  expect(find.text('Transferring'), findsOneWidget);
});

testWidgets('transfer route back cancels active transfer', (
  WidgetTester tester,
) async {
  final fakeSource = FakeSendTransferSource();
  final container = ProviderContainer(
    overrides: [
      initialAppSettingsProvider.overrideWithValue(testAppSettings),
      sendTransferSourceProvider.overrideWithValue(fakeSource),
    ],
  );
  addTearDown(container.dispose);

  final controller = container.read(sendControllerProvider.notifier);
  controller.beginDraft([
    SendPickedFile(
      path: '/tmp/report.pdf',
      name: 'report.pdf',
      sizeBytes: BigInt.from(1024),
    ),
  ]);
  controller.updateDestinationCode('ABC123');
  final request = controller.buildSendRequest()!;

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: SendTransferRoutePage(request: request)),
    ),
  );
  await tester.pump();

  await tester.pageBack();
  await tester.pumpAndSettle();

  expect(fakeSource.cancelCalled, isTrue);
  expect(container.read(sendControllerProvider).phase, SendSessionPhase.drafting);
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
flutter test test/features/send/send_feature_test.dart test/app_router_test.dart test/shell/drift_shell_test.dart test/features/send/presentation/send_transfer_route_test.dart -r expanded
```

Expected: FAIL until the placeholder text, direct transfer route behavior, and back/cancel paths are aligned.

- [ ] **Step 3: Write the minimal implementation**

Update the send feature placeholder to include `transferring` and `result` so it matches the direct transfer route lifecycle.

Ensure the transfer route:
- cancels active transfer on back
- clears any active transfer subscription when leaving the route
- leaves the draft state intact when the user returns

Remove the old review-route file if it is still present in the app tree, and update any imports/tests that still reference it.

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
flutter test test/features/send/send_feature_test.dart test/app_router_test.dart test/shell/drift_shell_test.dart test/features/send/presentation/send_transfer_route_test.dart -r expanded
flutter analyze lib test
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/send/send_feature.dart app/lib/features/send/presentation/send_transfer_route.dart app/lib/features/send/presentation/send_draft_preview.dart app/lib/app/app_router.dart app/test/features/send/send_feature_test.dart app/test/app_router_test.dart app/test/shell/drift_shell_test.dart app/test/features/send/presentation/send_transfer_route_test.dart
git commit -m "feat: polish send transfer route flow"
```

---

### Task 5: Verify the full send flow

**Files:**
- All files changed in Tasks 1-4

- [ ] **Step 1: Run the focused send tests**

Run:

```bash
flutter test test/features/send/application/state_test.dart test/features/send/application/controller_test.dart test/features/send/presentation/send_draft_preview_test.dart test/features/send/presentation/send_transfer_route_test.dart -r expanded
```

Expected: PASS.

- [ ] **Step 2: Run the broader app regression tests**

Run:

```bash
flutter test test/shell/drift_shell_test.dart test/app_router_test.dart test/features/send/send_feature_test.dart -r expanded
```

Expected: PASS.

- [ ] **Step 3: Run analyzer**

Run:

```bash
flutter analyze lib test
```

Expected: No issues found.

- [ ] **Step 4: Commit remaining changes**

```bash
git add app/lib/features/send/application/model.dart app/lib/features/send/application/state.dart app/lib/features/send/application/controller.dart app/lib/features/send/presentation/send_draft_preview.dart app/lib/features/send/presentation/send_transfer_route.dart app/lib/app/app_router.dart app/lib/features/send/send_feature.dart app/test/features/send/application/state_test.dart app/test/features/send/application/controller_test.dart app/test/features/send/presentation/send_draft_preview_test.dart app/test/features/send/presentation/send_transfer_route_test.dart app/test/features/send/send_feature_test.dart app/test/app_router_test.dart app/test/shell/drift_shell_test.dart
git commit -m "feat: add direct send transfer route flow"
```

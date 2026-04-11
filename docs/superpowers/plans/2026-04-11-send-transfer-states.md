# Send Transfer States Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Flutter send transfer page show the same visible phases as `ref-app` while keeping the controller-owned flow small and explicit.

**Architecture:** Keep `SendController` as the lifecycle owner, but enrich it with a dedicated transfer state object that preserves FRB phase, summary, plan, and snapshot data. Move the phase-to-UI mapping into a small presentation helper so the transfer route can render `connecting`, `waitingForDecision`, `accepted`, `sending`, and the terminal outcomes without turning the page into a second controller.

**Tech Stack:** Flutter, Riverpod, GoRouter, Flutter Rust Bridge, `flutter_test`

---

### Task 1: Introduce explicit transfer state in the send application layer

**Files:**
- Create: `app/lib/features/send/application/transfer_state.dart`
- Modify: `app/lib/features/send/application/state.dart`
- Modify: `app/lib/features/send/application/controller.dart`
- Test: `app/test/features/send/application/controller_test.dart`

- [ ] **Step 1: Write the failing tests**

Add tests that describe the richer transfer lifecycle and prove that the controller preserves the FRB update data.

```dart
test('send controller stores connecting, waiting, accepted, and sending transfer states', () {
  final fakeSource = FakeSendTransferSource();
  final container = ProviderContainer(
    overrides: [
      initialAppSettingsProvider.overrideWithValue(testAppSettings),
      sendTransferSourceProvider.overrideWithValue(fakeSource),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(fakeSource.close);

  final controller = container.read(sendControllerProvider.notifier);
  controller.beginDraft([
    SendPickedFile(
      path: '/tmp/report.pdf',
      name: 'report.pdf',
      sizeBytes: BigInt.from(1024),
    ),
  ]);
  controller.updateDestinationCode('ABC123');
  controller.startTransfer(controller.buildSendRequest()!);

  fakeSource.emit(
    SendTransferUpdate(
      phase: SendTransferUpdatePhase.waitingForDecision,
      destinationLabel: 'Laptop',
      statusMessage: 'Waiting for confirmation.',
      itemCount: BigInt.one,
      totalSize: BigInt.from(1024),
      bytesSent: BigInt.zero,
      totalBytes: BigInt.from(1024),
    ),
  );

  final state = container.read(sendControllerProvider);
  expect(state.phase, SendSessionPhase.transferring);
  expect(state.transfer?.phase, SendTransferSessionPhase.waitingForDecision);
  expect(state.transfer?.destinationLabel, 'Laptop');
  expect(state.transfer?.statusMessage, 'Waiting for confirmation.');
});
```

Add a second test that covers the terminal outcomes:

```dart
test('send controller maps completed declined cancelled and failed into result state', () {
  final fakeSource = FakeSendTransferSource();
  final container = ProviderContainer(
    overrides: [
      initialAppSettingsProvider.overrideWithValue(testAppSettings),
      sendTransferSourceProvider.overrideWithValue(fakeSource),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(fakeSource.close);

  final controller = container.read(sendControllerProvider.notifier);
  controller.beginDraft([
    SendPickedFile(
      path: '/tmp/report.pdf',
      name: 'report.pdf',
      sizeBytes: BigInt.from(1024),
    ),
  ]);
  controller.updateDestinationCode('ABC123');
  controller.startTransfer(controller.buildSendRequest()!);

  final fixtures = <({
    SendTransferUpdate update,
    SendTransferOutcome outcome,
    String title,
  })>[
    (
      update: SendTransferUpdate.completed(
        destinationLabel: 'Laptop',
        statusMessage: 'Sent successfully',
        itemCount: BigInt.one,
        totalSize: BigInt.from(1024),
        bytesSent: BigInt.from(1024),
      ),
      outcome: SendTransferOutcome.success,
      title: 'Sent',
    ),
    (
      update: SendTransferUpdate.declined(
        destinationLabel: 'Laptop',
        statusMessage: 'Receiver declined',
        itemCount: BigInt.one,
        totalSize: BigInt.from(1024),
        bytesSent: BigInt.zero,
        totalBytes: BigInt.from(1024),
      ),
      outcome: SendTransferOutcome.declined,
      title: 'Declined',
    ),
    (
      update: SendTransferUpdate.cancelled(
        destinationLabel: 'Laptop',
        statusMessage: 'Cancelled',
        itemCount: BigInt.one,
        totalSize: BigInt.from(1024),
        bytesSent: BigInt.zero,
        totalBytes: BigInt.from(1024),
      ),
      outcome: SendTransferOutcome.cancelled,
      title: 'Cancelled',
    ),
    (
      update: SendTransferUpdate.failed(
        destinationLabel: 'Laptop',
        statusMessage: 'Failed',
        itemCount: BigInt.one,
        totalSize: BigInt.from(1024),
        bytesSent: BigInt.zero,
        totalBytes: BigInt.from(1024),
        error: const SendTransferErrorData(
          kind: SendTransferErrorKind.internal,
          title: 'Send failed',
          message: 'boom',
          retryable: false,
        ),
      ),
      outcome: SendTransferOutcome.failed,
      title: 'Send failed',
    ),
  ];

  for (final fixture in fixtures) {
    fakeSource.emit(fixture.update);
    final state = container.read(sendControllerProvider);
    expect(state.phase, SendSessionPhase.result);
    expect(state.result?.outcome, fixture.outcome);
    expect(state.result?.title, fixture.title);
  }
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
flutter test test/features/send/application/controller_test.dart -r expanded
```

Expected: FAIL because `SendState` does not yet preserve the richer transfer phase data.

- [ ] **Step 3: Write the minimal implementation**

Create a dedicated transfer state object and teach the controller to preserve it:

```dart
@immutable
class SendTransferState {
  const SendTransferState({
    required this.phase,
    required this.destinationLabel,
    required this.statusMessage,
    required this.itemCount,
    required this.totalSize,
    required this.bytesSent,
    required this.totalBytes,
    this.plan,
    this.snapshot,
    this.remoteDeviceType,
    this.error,
  });

  final SendTransferSessionPhase phase;
  final String destinationLabel;
  final String statusMessage;
  final BigInt itemCount;
  final BigInt totalSize;
  final BigInt bytesSent;
  final BigInt totalBytes;
  final TransferPlanData? plan;
  final TransferSnapshotData? snapshot;
  final String? remoteDeviceType;
  final SendTransferErrorData? error;
}
```

Update `SendState` so `transferring` and `result` carry a `SendTransferState` instead of flattening every FRB field into controller-only logic:

```dart
const SendState.transferring({
  required List<SendDraftItem> items,
  required SendDestinationState destination,
  required SendRequestData request,
  required SendTransferState transfer,
}) : this._(
  phase: SendSessionPhase.transferring,
  items: items,
  destination: destination,
  request: request,
  transfer: transfer,
  result: null,
  errorMessage: null,
);
```

Map FRB updates in `controller.dart` with explicit phase handling:

```dart
void _handleTransferUpdate(SendTransferUpdate update) {
  if (state.phase != SendSessionPhase.transferring || state.request == null) {
    return;
  }

  final transfer = state.transfer!;
  final nextTransfer = SendTransferState(
    phase: switch (update.phase) {
      SendTransferUpdatePhase.connecting => SendTransferSessionPhase.connecting,
      SendTransferUpdatePhase.waitingForDecision => SendTransferSessionPhase.waitingForDecision,
      SendTransferUpdatePhase.accepted => SendTransferSessionPhase.accepted,
      SendTransferUpdatePhase.sending => SendTransferSessionPhase.sending,
      SendTransferUpdatePhase.completed => SendTransferSessionPhase.completed,
      SendTransferUpdatePhase.cancelled => SendTransferSessionPhase.cancelled,
      SendTransferUpdatePhase.declined => SendTransferSessionPhase.declined,
      SendTransferUpdatePhase.failed => SendTransferSessionPhase.failed,
    },
    destinationLabel: update.destinationLabel,
    statusMessage: update.statusMessage,
    itemCount: update.itemCount,
    totalSize: update.totalSize,
    bytesSent: update.bytesSent,
    totalBytes: update.totalBytes,
    plan: update.plan ?? transfer.plan,
    snapshot: update.snapshot ?? transfer.snapshot,
    remoteDeviceType: update.remoteDeviceType ?? transfer.remoteDeviceType,
    error: update.error ?? transfer.error,
  );

  // Terminal phases become result state; progress phases stay in transferring.
}
```

Keep terminal transitions explicit:

```dart
case SendTransferUpdatePhase.completed:
case SendTransferUpdatePhase.declined:
case SendTransferUpdatePhase.cancelled:
case SendTransferUpdatePhase.failed:
  state = SendState.result(
    items: state.items,
    destination: state.destination,
    request: state.request!,
    transfer: nextTransfer,
    result: ...,
  );
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
flutter test test/features/send/application/controller_test.dart -r expanded
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/send/application/transfer_state.dart app/lib/features/send/application/state.dart app/lib/features/send/application/controller.dart app/test/features/send/application/controller_test.dart
git commit -m "feat: model send transfer phases"
```

---

### Task 2: Render the transfer route like the reference app

**Files:**
- Modify: `app/lib/features/send/presentation/send_transfer_route.dart`
- Create: `app/lib/features/send/presentation/send_transfer_view.dart`
- Modify: `app/test/features/send/presentation/send_transfer_route_test.dart`

- [ ] **Step 1: Write the failing widget tests**

Add tests that pin the visible behavior for each major state:

```dart
testWidgets('send transfer route shows waiting for decision state', (WidgetTester tester) async {
  final fakeSource = FakeSendTransferSource();
  final container = ProviderContainer(
    overrides: [
      initialAppSettingsProvider.overrideWithValue(testAppSettings),
      sendTransferSourceProvider.overrideWithValue(fakeSource),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(fakeSource.close);

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
  fakeSource.emit(
    SendTransferUpdate(
      phase: SendTransferUpdatePhase.waitingForDecision,
      destinationLabel: 'Laptop',
      statusMessage: 'Waiting for confirmation.',
      itemCount: BigInt.one,
      totalSize: BigInt.from(1024),
      bytesSent: BigInt.zero,
      totalBytes: BigInt.from(1024),
    ),
  );
  await tester.pump();

  expect(find.text('Waiting for confirmation.'), findsOneWidget);
  expect(find.text('/tmp/report.pdf'), findsOneWidget);
});

testWidgets('send transfer route shows sending progress and per-file progress', (WidgetTester tester) async {
  final fakeSource = FakeSendTransferSource();
  final container = ProviderContainer(
    overrides: [
      initialAppSettingsProvider.overrideWithValue(testAppSettings),
      sendTransferSourceProvider.overrideWithValue(fakeSource),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(fakeSource.close);

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

  fakeSource.emit(
    SendTransferUpdate(
      phase: SendTransferUpdatePhase.sending,
      destinationLabel: 'Laptop',
      statusMessage: 'Sending files.',
      itemCount: BigInt.one,
      totalSize: BigInt.from(1024),
      bytesSent: BigInt.from(512),
      totalBytes: BigInt.from(1024),
      remoteDeviceType: 'laptop',
    ),
  );
  await tester.pump();

  expect(find.text('Sending files.'), findsOneWidget);
  expect(find.textContaining('512'), findsOneWidget);
});

testWidgets('send transfer route shows completed declined cancelled and failed result cards', (WidgetTester tester) async {
  final fixtures = <({
    SendTransferUpdate update,
    String title,
  })>[
    (
      update: SendTransferUpdate.completed(
        destinationLabel: 'Laptop',
        statusMessage: 'Sent successfully',
        itemCount: BigInt.one,
        totalSize: BigInt.from(1024),
        bytesSent: BigInt.from(1024),
      ),
      title: 'Sent',
    ),
    (
      update: SendTransferUpdate.declined(
        destinationLabel: 'Laptop',
        statusMessage: 'Receiver declined',
        itemCount: BigInt.one,
        totalSize: BigInt.from(1024),
        bytesSent: BigInt.zero,
        totalBytes: BigInt.from(1024),
      ),
      title: 'Declined',
    ),
    (
      update: SendTransferUpdate.cancelled(
        destinationLabel: 'Laptop',
        statusMessage: 'Cancelled',
        itemCount: BigInt.one,
        totalSize: BigInt.from(1024),
        bytesSent: BigInt.zero,
        totalBytes: BigInt.from(1024),
      ),
      title: 'Cancelled',
    ),
    (
      update: SendTransferUpdate.failed(
        destinationLabel: 'Laptop',
        statusMessage: 'Failed',
        itemCount: BigInt.one,
        totalSize: BigInt.from(1024),
        bytesSent: BigInt.zero,
        totalBytes: BigInt.from(1024),
        error: const SendTransferErrorData(
          kind: SendTransferErrorKind.internal,
          title: 'Send failed',
          message: 'boom',
          retryable: false,
        ),
      ),
      title: 'Send failed',
    ),
  ];

  for (final fixture in fixtures) {
    final fakeSource = FakeSendTransferSource();
    final container = ProviderContainer(
      overrides: [
        initialAppSettingsProvider.overrideWithValue(testAppSettings),
        sendTransferSourceProvider.overrideWithValue(fakeSource),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(fakeSource.close);

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
    fakeSource.emit(fixture.update);
    await tester.pump();

    expect(find.text(fixture.title), findsOneWidget);
  }
});
```

The page should still start transfer on entry and should still cancel when navigating back.

- [ ] **Step 2: Run the widget tests to verify they fail**

Run:

```bash
flutter test test/features/send/presentation/send_transfer_route_test.dart -r expanded
```

Expected: FAIL because the route still only renders the simple waiting/transferring/result card.

- [ ] **Step 3: Write the minimal UI implementation**

Use a small helper widget file to keep the route readable:

```dart
class SendTransferView extends StatelessWidget {
  const SendTransferView({required this.state, required this.request, super.key});

  final SendState state;
  final SendRequestData request;

  @override
  Widget build(BuildContext context) {
    return switch (state.transfer?.phase) {
      SendTransferSessionPhase.connecting => _TransferBanner(
        title: 'Request sent',
        message: 'Starting transfer to ${state.transfer!.destinationLabel}.',
      ),
      SendTransferSessionPhase.waitingForDecision => _TransferBanner(
        title: 'Waiting for confirmation',
        message: 'Waiting for the receiver to approve the transfer.',
      ),
      SendTransferSessionPhase.accepted => _TransferBanner(
        title: 'Receiver confirmed',
        message: 'Preparing files for transfer.',
      ),
      SendTransferSessionPhase.sending => _SendingView(state: state),
      SendTransferSessionPhase.completed ||
      SendTransferSessionPhase.declined ||
      SendTransferSessionPhase.cancelled ||
      SendTransferSessionPhase.failed => _TransferResultView(state: state),
      null => const SizedBox.shrink(),
    };
  }
}
```

Render the file list from `state.transfer?.plan` and `state.transfer?.snapshot` so completed rows are marked done and the active row shows progress.

Render the result card from `state.result` using the same outcome colors already used in the draft page, and include the completion metrics rows when `state.transfer?.phase == SendTransferSessionPhase.completed`.

- [ ] **Step 4: Run the widget tests to verify they pass**

Run:

```bash
flutter test test/features/send/presentation/send_transfer_route_test.dart -r expanded
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/send/presentation/send_transfer_route.dart app/lib/features/send/presentation/send_transfer_view.dart app/test/features/send/presentation/send_transfer_route_test.dart
git commit -m "feat: render send transfer states"
```

---

### Task 3: Verify the full send flow and clean up stale transfer assumptions

**Files:**
- Modify: `app/test/features/send/presentation/send_draft_preview_test.dart`
- Modify: `app/test/features/send/application/controller_test.dart`
- Modify: `app/lib/features/send/send_feature.dart`
- Modify: `app/lib/features/send/application/state.dart` if any getters need to expose the new transfer data to presentation

- [ ] **Step 1: Write the failing regression tests**

Add a small regression test that ensures the draft page still routes into the new transfer page and that the feature placeholder reflects the new lifecycle:

```dart
testWidgets('tapping Send still pushes the transfer route', (WidgetTester tester) async {
  final fakeSource = FakeSendTransferSource();
  final container = _buildContainer(
    directorySizeCalculator: FakeDirectorySizeCalculator({}),
    receiverSource: FakeReceiverServiceSource(),
    picker: FakeSendSelectionPicker(),
    overrides: [
      sendTransferSourceProvider.overrideWithValue(fakeSource),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(fakeSource.close);

  container.read(sendControllerProvider.notifier).beginDraft([
    SendPickedFile(
      path: '/tmp/report.pdf',
      name: 'report.pdf',
      sizeBytes: BigInt.from(1024),
    ),
  ]);
  container.read(sendControllerProvider.notifier).updateDestinationCode('ABC123');

  final router = GoRouter(
    initialLocation: AppRoutePaths.sendDraft,
    routes: [
      GoRoute(
        path: AppRoutePaths.home,
        builder: (context, state) => const SizedBox.shrink(),
        routes: [
          GoRoute(
            path: AppRoutePaths.sendDraftSegment,
            builder: (context, state) => const SendDraftPreview(),
          ),
          GoRoute(
            path: AppRoutePaths.sendTransferSegment,
            builder: (context, state) =>
                SendTransferRoutePage(request: state.extra as SendRequestData),
          ),
        ],
      ),
    ],
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump(const Duration(seconds: 1));

  await tester.tap(find.text('Send'));
  await tester.pump();

  expect(router.routeInformationProvider.value.uri.toString(), AppRoutePaths.sendTransfer);
});

test('send feature placeholder shows transfer state text for connecting waiting accepted and sending', () {
  final fakeSource = FakeSendTransferSource();
  final container = ProviderContainer(
    overrides: [
      initialAppSettingsProvider.overrideWithValue(testAppSettings),
      sendTransferSourceProvider.overrideWithValue(fakeSource),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(fakeSource.close);

  final controller = container.read(sendControllerProvider.notifier);
  controller.beginDraft([
    SendPickedFile(
      path: '/tmp/report.pdf',
      name: 'report.pdf',
      sizeBytes: BigInt.from(1024),
    ),
  ]);
  controller.updateDestinationCode('ABC123');

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SendFeaturePlaceholder()),
    ),
  );
  await tester.pump();

  controller.startTransfer(controller.buildSendRequest()!);
  await tester.pump();
  expect(find.text('Connecting'), findsOneWidget);

  fakeSource.emit(
    SendTransferUpdate(
      phase: SendTransferUpdatePhase.waitingForDecision,
      destinationLabel: 'Laptop',
      statusMessage: 'Waiting for confirmation.',
      itemCount: BigInt.one,
      totalSize: BigInt.from(1024),
      bytesSent: BigInt.zero,
      totalBytes: BigInt.from(1024),
    ),
  );
  await tester.pump();
  expect(find.text('Waiting for decision'), findsOneWidget);

  fakeSource.emit(
    SendTransferUpdate(
      phase: SendTransferUpdatePhase.accepted,
      destinationLabel: 'Laptop',
      statusMessage: 'Receiver confirmed.',
      itemCount: BigInt.one,
      totalSize: BigInt.from(1024),
      bytesSent: BigInt.zero,
      totalBytes: BigInt.from(1024),
    ),
  );
  await tester.pump();
  expect(find.text('Accepted'), findsOneWidget);

  fakeSource.emit(
    SendTransferUpdate(
      phase: SendTransferUpdatePhase.sending,
      destinationLabel: 'Laptop',
      statusMessage: 'Sending files.',
      itemCount: BigInt.one,
      totalSize: BigInt.from(1024),
      bytesSent: BigInt.from(512),
      totalBytes: BigInt.from(1024),
    ),
  );
  await tester.pump();
  expect(find.text('Sending'), findsOneWidget);
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
flutter test test/features/send/presentation/send_draft_preview_test.dart test/features/send/application/controller_test.dart -r expanded
```

Expected: FAIL if any stale review-route or coarse transfer-state assumptions remain.

- [ ] **Step 3: Make the final cleanup**

Update the placeholder and any remaining getters so the send feature surfaces the richer transfer lifecycle cleanly:

```dart
status: switch (state.phase) {
  SendSessionPhase.idle => 'Send is idle',
  SendSessionPhase.drafting => 'Drafting',
  SendSessionPhase.transferring => switch (state.transfer?.phase) {
    SendTransferSessionPhase.connecting => 'Connecting',
    SendTransferSessionPhase.waitingForDecision => 'Waiting for decision',
    SendTransferSessionPhase.accepted => 'Accepted',
    SendTransferSessionPhase.sending => 'Sending',
    SendTransferSessionPhase.cancelled => 'Cancelled',
    SendTransferSessionPhase.completed => 'Completed',
    SendTransferSessionPhase.declined => 'Declined',
    SendTransferSessionPhase.failed => 'Failed',
    null => 'Transferring',
  },
  SendSessionPhase.result => 'Result',
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
flutter test test/features/send/application/controller_test.dart test/features/send/presentation/send_draft_preview_test.dart test/features/send/presentation/send_transfer_route_test.dart -r expanded
flutter analyze lib test
```

Expected: PASS for tests and no analyzer issues.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/send/send_feature.dart app/lib/features/send/application/state.dart app/test/features/send/application/controller_test.dart app/test/features/send/presentation/send_draft_preview_test.dart
git commit -m "test: cover send transfer lifecycle states"
```

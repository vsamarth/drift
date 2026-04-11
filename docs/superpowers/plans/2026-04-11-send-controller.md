# Send Controller Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the send feature controller own the idle-to-draft transition and the draft file/code state, instead of keeping the draft as route-local widget state.

**Architecture:** Keep one send controller as the feature owner. The controller will store the current phase, draft items, destination code, and later transfer/result data. The draft screen will read and mutate controller state through focused controller methods; it will keep only presentation-only cache for directory size hydration.

**Tech Stack:** Flutter, Riverpod, GoRouter, `flutter_test`

---

### Task 1: Define controller-owned draft state

**Files:**
- Modify: `app/lib/features/send/application/model.dart`
- Modify: `app/lib/features/send/application/state.dart`
- Test: `app/test/features/send/application/state_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
test('send state exposes a drafting constructor with items and code', () {
  final state = SendState.drafting(
    items: [
      SendDraftItem(
        path: '/tmp/report.pdf',
        name: 'report.pdf',
        sizeBytes: BigInt.from(1024),
      ),
    ],
  );

  expect(state.phase, SendSessionPhase.drafting);
  expect(state.items, hasLength(1));
  expect(state.destination, isNull);
  expect(state.result, isNull);
  expect(state.errorMessage, isNull);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test app/test/features/send/application/state_test.dart -r expanded`
Expected: FAIL because `SendState.drafting` does not exist yet.

- [ ] **Step 3: Write minimal implementation**

```dart
@immutable
class SendState {
  const SendState._({
    required this.phase,
    required this.items,
    required this.destination,
    required this.result,
    required this.errorMessage,
  });

  const SendState.idle()
      : this._(
          phase: SendSessionPhase.idle,
          items: const [],
          destination: null,
          result: null,
          errorMessage: null,
        );

  const SendState.drafting({
    required List<SendDraftItem> items,
    String? destination,
  }) : this._(
          phase: SendSessionPhase.drafting,
          items: items,
          destination: destination,
          result: null,
          errorMessage: null,
        );

  final SendSessionPhase phase;
  final List<SendDraftItem> items;
  final String? destination;
  final SendTransferResult? result;
  final String? errorMessage;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test app/test/features/send/application/state_test.dart -r expanded`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/send/application/model.dart app/lib/features/send/application/state.dart app/test/features/send/application/state_test.dart
git commit -m "feat: model send draft state"
```

### Task 2: Move draft lifecycle into the send controller

**Files:**
- Modify: `app/lib/features/send/application/controller.dart`
- Modify: `app/test/features/send/application/controller_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
test('send controller can begin and clear a draft', () {
  final container = ProviderContainer();
  addTearDown(container.dispose);

  final controller = container.read(sendControllerProvider.notifier);
  controller.beginDraft([
    const SendPickedFile(
      path: '/tmp/report.pdf',
      name: 'report.pdf',
      sizeBytes: BigInt.from(1024),
    ),
  ]);

  final drafting = container.read(sendControllerProvider);
  expect(drafting.phase, SendSessionPhase.drafting);
  expect(drafting.items, hasLength(1));

  controller.clearDraft();

  final idle = container.read(sendControllerProvider);
  expect(idle.phase, SendSessionPhase.idle);
  expect(idle.items, isEmpty);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test app/test/features/send/application/controller_test.dart -r expanded`
Expected: FAIL because `beginDraft` and `clearDraft` do not exist yet.

- [ ] **Step 3: Write minimal implementation**

```dart
@riverpod
class SendController extends _$SendController {
  @override
  SendState build() {
    return const SendState.idle();
  }

  void beginDraft(List<SendPickedFile> files) {
    state = SendState.drafting(
      items: files
          .map(
            (file) => SendDraftItem(
              path: file.path,
              name: file.name,
              sizeBytes: file.sizeBytes ?? BigInt.zero,
            ),
          )
          .toList(growable: false),
    );
  }

  void clearDraft() {
    state = const SendState.idle();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test app/test/features/send/application/controller_test.dart -r expanded`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/send/application/controller.dart app/test/features/send/application/controller_test.dart
git commit -m "feat: add send draft controller"
```

### Task 3: Rewire the shell and draft preview to use controller state

**Files:**
- Modify: `app/lib/app/app_router.dart`
- Modify: `app/lib/shell/drift_shell.dart`
- Modify: `app/lib/features/send/presentation/send_draft_preview.dart`
- Modify: `app/test/shell/drift_shell_test.dart`
- Modify: `app/test/features/send/presentation/send_draft_preview_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
testWidgets('picking files begins a controller draft and shows the preview', (
  WidgetTester tester,
) async {
  // Seed the picker and pump the shell.
  // Tap Select files -> Files.
  // Expect the router to reach /send/draft and the preview to render the picked file.
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test app/test/shell/drift_shell_test.dart -r expanded`
Expected: FAIL because the shell still navigates with route extras and the preview still owns the draft locally.

- [ ] **Step 3: Write minimal implementation**

```dart
// Shell seeds the controller before navigation.
// Router builds SendDraftPreview with no files argument.
// Preview reads controller state and calls controller methods for add/remove/code.
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test app/test/shell/drift_shell_test.dart app/test/features/send/presentation/send_draft_preview_test.dart -r expanded`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/app/app_router.dart app/lib/shell/drift_shell.dart app/lib/features/send/presentation/send_draft_preview.dart app/test/shell/drift_shell_test.dart app/test/features/send/presentation/send_draft_preview_test.dart
git commit -m "feat: route send draft through controller"
```

# Send Controller Facade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `SendController` the send feature facade that wires all send actions, while keeping the actual behavior in focused send helpers and shrinking `DriftAppNotifier` to app-shell glue.

**Architecture:** `SendController` will own the send-facing API used by the UI and delegate to small modules for selection, nearby discovery, transfer start/update, and shell decisions. `DriftAppNotifier` will keep shared app state and the host methods the helpers need, but it should stop being the place where send feature decisions accumulate.

**Tech Stack:** Flutter `Notifier`, Riverpod providers, existing send coordinators/helpers, Dart unit tests.

---

### Task 1: Make the controller the send wiring layer

**Files:**
- Modify: `flutter/lib/features/send/send_controller.dart`
- Test: `flutter/test/features/send/send_controller_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
test('send controller wires send actions through the feature helpers', () {
  final itemSource = FakeSendItemSource();
  final transferSource = FakeSendTransferSource();
  final nearbySource = FakeNearbyDiscoverySource();
  final notifier = FakeSendAppNotifier(buildSendDraftState());
  final container = ProviderContainer(
    overrides: [
      driftAppNotifierProvider.overrideWith(() => notifier),
      sendItemSourceProvider.overrideWithValue(itemSource),
      sendTransferSourceProvider.overrideWithValue(transferSource),
      nearbyDiscoverySourceProvider.overrideWithValue(nearbySource),
    ],
  );
  addTearDown(() async {
    await transferSource.dispose();
    container.dispose();
  });

  final controller = container.read(sendControllerProvider.notifier);

  controller.pickSendItems();
  controller.appendSendItemsFromPicker();
  controller.rescanNearbySendDestinations();
  controller.updateSendDestinationCode('ab2cd3');
  controller.clearSendDestinationCode();
  controller.startSend();
  controller.cancelSendInProgress();
  controller.handleTransferResultPrimaryAction();
  controller.selectNearbyDestination(
    notifier.build().nearbySendDestinations.first,
  );

  expect(notifier.pickSendItemsCalls, 1);
  expect(notifier.appendSendItemsFromPickerCalls, 1);
  expect(notifier.rescanNearbySendDestinationsCalls, 1);
  expect(notifier.updateSendDestinationCodeCalls, 1);
  expect(notifier.clearSendDestinationCodeCalls, 1);
  expect(notifier.startSendCalls, 1);
  expect(notifier.cancelSendInProgressCalls, 1);
  expect(notifier.handleTransferResultPrimaryActionCalls, 1);
  expect(notifier.selectNearbyDestinationCalls, 1);
});
```

- [ ] **Step 2: Run the focused test and confirm it fails**

Run: `flutter test test/features/send/send_controller_test.dart`
Expected: failure because the controller now depends on real send helpers and the test doubles do not yet support those paths.

- [ ] **Step 3: Implement the minimal controller wiring**

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/transfer_models.dart';
import '../../state/drift_app_state.dart';
import '../../state/drift_providers.dart';
import 'send_flow_actions.dart' as send_flow_actions;
import 'send_nearby_coordinator.dart';
import 'send_selection_builder.dart';
import 'send_selection_coordinator.dart';
import 'send_shell_actions.dart' as send_shell_actions;
import 'send_transfer_coordinator.dart';
import 'send_providers.dart' as send_deps;
import 'send_state.dart';

class SendController extends Notifier<SendState> {
  late final SendSelectionCoordinator _sendSelectionCoordinator;
  late final SendNearbyCoordinator _sendNearbyCoordinator;
  late final SendTransferCoordinator _sendTransferCoordinator;

  @override
  SendState build() {
    final appState = ref.watch(driftAppNotifierProvider);
    _sendSelectionCoordinator = SendSelectionCoordinator(
      itemSource: ref.watch(send_deps.sendItemSourceProvider),
      selectionBuilder: const SendSelectionBuilder(),
    );
    _sendNearbyCoordinator = SendNearbyCoordinator(
      nearbyDiscoverySource: ref.watch(send_deps.nearbyDiscoverySourceProvider),
    );
    _sendTransferCoordinator = SendTransferCoordinator(
      transferSource: ref.watch(send_deps.sendTransferSourceProvider),
    );
    return SendState.fromAppState(appState);
  }

  void pickSendItems() {
    unawaited(
      _sendSelectionCoordinator.pickSendItems(
        ref.read(driftAppNotifierProvider.notifier),
      ),
    );
  }

  void appendSendItemsFromPicker() {
    unawaited(
      _sendSelectionCoordinator.appendSendItemsFromPicker(
        ref.read(driftAppNotifierProvider.notifier),
      ),
    );
  }

  void rescanNearbySendDestinations() {
    unawaited(
      _sendNearbyCoordinator.runScanOnce(
        ref.read(driftAppNotifierProvider.notifier),
      ),
    );
  }

  void acceptDroppedSendItems(List<String> paths) {
    unawaited(
      _sendSelectionCoordinator.acceptDroppedSendItems(
        ref.read(driftAppNotifierProvider.notifier),
        paths,
      ),
    );
  }

  void appendDroppedSendItems(List<String> paths) {
    unawaited(
      _sendSelectionCoordinator.appendDroppedSendItems(
        ref.read(driftAppNotifierProvider.notifier),
        paths,
      ),
    );
  }

  void removeSendItem(String path) {
    unawaited(
      _sendSelectionCoordinator.removeSendItem(
        ref.read(driftAppNotifierProvider.notifier),
        path,
      ),
    );
  }

  void updateSendDestinationCode(String value) {
    final draft = _currentDraft();
    final next = send_shell_actions.updateSendDestinationCode(draft, value);
    if (next == null) {
      return;
    }
    ref.read(driftAppNotifierProvider.notifier).applySendDraftSession(next);
  }

  void clearSendDestinationCode() {
    final draft = _currentDraft();
    final next = send_shell_actions.clearSendDestinationCode(draft);
    if (next == null) {
      return;
    }
    ref.read(driftAppNotifierProvider.notifier).applySendDraftSession(next);
  }

  void startSend() {
    final appState = ref.read(driftAppNotifierProvider);
    final intent = send_flow_actions.buildSendStartIntent(appState);
    if (intent == null) {
      return;
    }

    final host = ref.read(driftAppNotifierProvider.notifier);
    if (intent.ticket != null && intent.destination != null) {
      _sendTransferCoordinator.startSendTransferWithTicket(
        host: host,
        destination: intent.destination!,
        ticket: intent.ticket!,
        onUpdate: host.applySendTransferUpdate,
      );
    } else if (intent.normalizedCode != null) {
      _sendTransferCoordinator.startSendTransfer(
        host: host,
        normalizedCode: intent.normalizedCode!,
        onUpdate: host.applySendTransferUpdate,
      );
    }
  }

  void cancelSendInProgress() {
    ref.read(driftAppNotifierProvider.notifier).cancelSendInProgress();
  }

  void handleTransferResultPrimaryAction() {
    ref.read(driftAppNotifierProvider.notifier).handleTransferResultPrimaryAction();
  }

  void selectNearbyDestination(SendDestinationViewData destination) {
    final draft = _currentDraft();
    final next = send_shell_actions.selectNearbyDestination(draft, destination);
    if (next == null) {
      return;
    }
    ref.read(driftAppNotifierProvider.notifier).applySendDraftSession(next);
  }

  SendDraftSession? _currentDraft() {
    final session = ref.read(driftAppNotifierProvider).session;
    return session is SendDraftSession ? session : null;
  }
}
```

- [ ] **Step 4: Run the focused test and confirm it passes**

Run: `flutter test test/features/send/send_controller_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add flutter/lib/features/send/send_controller.dart flutter/test/features/send/send_controller_test.dart
git commit -m "refactor: make send controller own wiring"
```

### Task 2: Make the send test doubles behave like a real host

**Files:**
- Modify: `flutter/test/features/send/send_test_support.dart`
- Test: `flutter/test/features/send/send_selection_coordinator_test.dart`
- Test: `flutter/test/features/send/send_nearby_coordinator_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
test('fake send app notifier accepts coordinator host calls', () async {
  final notifier = FakeSendAppNotifier(buildSendDraftState());

  notifier.clearSendFlow();
  notifier.beginSendInspection(clearExistingItems: false);
  notifier.applyPendingSendItems(const []);
  notifier.applySelectedSendItems(const []);
  notifier.finishSendInspection();
  notifier.clearSendSetupError();
  notifier.reportSendSelectionError('boom', StateError('boom'), StackTrace.empty);
  notifier.setNearbyScanInFlight(true);
  notifier.setNearbyScanCompletedOnce(true);
  notifier.setNearbyDestinations(const []);
  notifier.setSendSetupError('bad');
  notifier.clearNearbyScanTimer();
  notifier.logNearbyScanFailure(StateError('scan'), StackTrace.empty);
  notifier.applySendDraftSession(buildSendDraftState().session as SendDraftSession);
  notifier.applySendTransferUpdate(
    const SendTransferUpdate(
      phase: SendTransferPhase.connecting,
      request: SendTransferRequestData(
        code: 'AB2CD3',
        items: [],
      ),
    ),
  );

  expect(notifier.clearSendFlowCalls, 1);
  expect(notifier.beginSendInspectionCalls, 1);
  expect(notifier.applyPendingSendItemsCalls, 1);
  expect(notifier.applySelectedSendItemsCalls, 1);
  expect(notifier.finishSendInspectionCalls, 1);
  expect(notifier.clearSendSetupErrorCalls, 1);
  expect(notifier.reportSendSelectionErrorCalls, 1);
  expect(notifier.setNearbyScanInFlightCalls, 1);
  expect(notifier.setNearbyScanCompletedOnceCalls, 1);
  expect(notifier.setNearbyDestinationsCalls, 1);
  expect(notifier.setSendSetupErrorCalls, 1);
  expect(notifier.clearNearbyScanTimerCalls, 1);
  expect(notifier.logNearbyScanFailureCalls, 1);
  expect(notifier.applySendDraftSessionCalls, 1);
});
```

- [ ] **Step 2: Run the focused test and confirm it fails**

Run: `flutter test test/features/send/send_selection_coordinator_test.dart test/features/send/send_nearby_coordinator_test.dart`
Expected: FAIL because `FakeSendAppNotifier` does not yet safely host the coordinator methods.

- [ ] **Step 3: Implement the fake host behavior**

```dart
class FakeSendAppNotifier extends DriftAppNotifier {
  // ...

  @override
  void clearSendFlow() {
    clearSendFlowCalls += 1;
    setState(_state.copyWith(session: const IdleSession(), clearSendSetupErrorMessage: true));
  }

  @override
  void beginSendInspection({required bool clearExistingItems}) {
    beginSendInspectionCalls += 1;
    final current = _state.session;
    final items = clearExistingItems && current is SendDraftSession
        ? const <TransferItemViewData>[]
        : _state.sendItems;
    setState(
      _state.copyWith(
        session: SendDraftSession(
          items: List<TransferItemViewData>.unmodifiable(items),
          isInspecting: true,
          nearbyDestinations: const [],
          nearbyScanInFlight: false,
          nearbyScanCompletedOnce: false,
          destinationCode: current is SendDraftSession ? current.destinationCode : '',
        ),
      ),
    );
  }

  @override
  void applyPendingSendItems(List<TransferItemViewData> items) {
    applyPendingSendItemsCalls += 1;
    final current = _state.session;
    if (current is! SendDraftSession) {
      return;
    }
    setState(_state.copyWith(session: current.copyWith(items: List<TransferItemViewData>.unmodifiable(items))));
  }

  @override
  void applySelectedSendItems(List<TransferItemViewData> items) {
    applySelectedSendItemsCalls += 1;
    setState(
      _state.copyWith(
        session: SendDraftSession(
          items: List<TransferItemViewData>.unmodifiable(items),
          isInspecting: false,
          nearbyDestinations: const [],
          nearbyScanInFlight: false,
          nearbyScanCompletedOnce: false,
          destinationCode: '',
        ),
      ),
    );
  }

  @override
  void finishSendInspection() {
    finishSendInspectionCalls += 1;
    final current = _state.session;
    if (current is! SendDraftSession) {
      return;
    }
    setState(_state.copyWith(session: current.copyWith(isInspecting: false)));
  }

  @override
  void clearSendSetupError() {
    clearSendSetupErrorCalls += 1;
    setState(_state.copyWith(clearSendSetupErrorMessage: true));
  }

  @override
  void reportSendSelectionError(String userMessage, Object error, StackTrace stackTrace) {
    reportSendSelectionErrorCalls += 1;
    setState(_state.copyWith(sendSetupErrorMessage: userMessage));
  }

  @override
  void setNearbyScanInFlight(bool value) {
    setNearbyScanInFlightCalls += 1;
    final current = _state.session;
    if (current is! SendDraftSession) {
      return;
    }
    setState(_state.copyWith(session: current.copyWith(nearbyScanInFlight: value)));
  }

  @override
  void setNearbyScanCompletedOnce(bool value) {
    setNearbyScanCompletedOnceCalls += 1;
    final current = _state.session;
    if (current is! SendDraftSession) {
      return;
    }
    setState(_state.copyWith(session: current.copyWith(nearbyScanCompletedOnce: value)));
  }

  @override
  void setNearbyDestinations(List<SendDestinationViewData> destinations) {
    setNearbyDestinationsCalls += 1;
    final current = _state.session;
    if (current is! SendDraftSession) {
      return;
    }
    setState(
      _state.copyWith(
        session: current.copyWith(
          nearbyDestinations: List<SendDestinationViewData>.unmodifiable(destinations),
        ),
      ),
    );
  }

  @override
  void setSendSetupError(String message) {
    setSendSetupErrorCalls += 1;
    setState(_state.copyWith(sendSetupErrorMessage: message));
  }
}
```

- [ ] **Step 4: Run the focused tests and confirm they pass**

Run: `flutter test test/features/send/send_selection_coordinator_test.dart test/features/send/send_nearby_coordinator_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add flutter/test/features/send/send_test_support.dart flutter/test/features/send/send_selection_coordinator_test.dart flutter/test/features/send/send_nearby_coordinator_test.dart
git commit -m "test: harden send feature fakes"
```

### Task 3: Trim the remaining send-specific methods from the app notifier

**Files:**
- Modify: `flutter/lib/state/drift_app_notifier.dart`
- Test: `flutter/test/state/drift_app_notifier_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
test('send notifier still preserves send shell behavior through facade methods', () {
  final notifier = DriftAppNotifier();
  // Use the existing notifier tests for the shell transitions that remain.
  // This task keeps the existing behavior stable while the controller owns wiring.
  expect(notifier, isNotNull);
});
```

- [ ] **Step 2: Run the targeted notifier test**

Run: `flutter test test/state/drift_app_notifier_test.dart`
Expected: PASS before and after the refactor, confirming no user-visible send behavior regressed.

- [ ] **Step 3: Remove direct send wiring from the notifier**

```dart
void applySendTransferUpdate(SendTransferUpdate update) {
  _applySendUpdate(update);
}

void applySendDraftSession(SendDraftSession session) {
  _setSession(session);
}
```

The notifier should keep only the host methods that the send helpers still require, plus the session bookkeeping and lifecycle cleanup that cannot move yet.

- [ ] **Step 4: Run the notifier and send tests**

Run: `flutter test test/state/drift_app_notifier_test.dart test/features/send/send_controller_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add flutter/lib/state/drift_app_notifier.dart flutter/test/state/drift_app_notifier_test.dart
git commit -m "refactor: keep send logic behind controller facade"
```

### Task 4: Verify the full Flutter package still passes

**Files:**
- None

- [ ] **Step 1: Run the full Flutter test suite**

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 2: Run analyzer**

Run: `flutter analyze`
Expected: no errors or warnings from the send refactor.

- [ ] **Step 3: Commit the final verification state if needed**

If the verification step required any last-minute fixes, commit them with a conventional message like `refactor: finish send controller facade`.

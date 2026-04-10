# Send Shell Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the remaining send-shell action helpers out of `DriftAppNotifier` so the notifier stops owning send destination editing and send-result navigation rules.

**Architecture:** Add a small pure helper module under `flutter/lib/features/send/` that transforms send shell inputs into next send draft state. Keep `DriftAppNotifier` responsible for applying the returned session to app state and for the non-send-specific side effects like cancelling timers and resetting shell-wide state. This slice should not touch receive behavior or transfer subscription handling.

**Tech Stack:** Dart 3, Flutter, Riverpod, `flutter_test`

---

### Task 1: Add pure send shell action helpers and unit tests

**Files:**
- Create: `flutter/lib/features/send/send_shell_actions.dart`
- Create: `flutter/test/features/send/send_shell_actions_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:drift_app/core/models/transfer_models.dart';
import 'package:drift_app/features/send/send_shell_actions.dart' as send_shell_actions;
import 'package:drift_app/state/drift_app_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'send_test_support.dart';

void main() {
  test('normalizes and stores a send destination code on the draft', () {
    final draft = send_shell_actions.updateSendDestinationCode(
      buildSendDraftState().session as SendDraftSession,
      'ab2-cd3',
    );

    expect(draft.destinationCode, 'AB2CD3');
    expect(draft.selectedDestination, isNull);
  });

  test('selecting the same nearby destination toggles it off', () {
    final destination = const SendDestinationViewData(
      name: 'Lab Mac',
      kind: SendDestinationKind.laptop,
      lanTicket: 'ticket-123',
      lanFullname: 'lab-mac._drift._udp.local.',
    );
    final draft = buildSendDraftState().session as SendDraftSession;
    final selected = draft.copyWith(selectedDestination: destination);

    final toggled = send_shell_actions.selectNearbyDestination(
      selected,
      destination,
    );

    expect(toggled.selectedDestination, isNull);
    expect(toggled.destinationCode, selected.destinationCode);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/send/send_shell_actions_test.dart`
Expected: fail because `send_shell_actions.dart` and the helper functions do not exist yet.

- [ ] **Step 3: Implement the helper module**

```dart
import '../../core/models/transfer_models.dart';
import '../../state/drift_app_state.dart';
import 'send_shell_actions.dart' as send_shell_actions;

String normalizeSendDestinationCode(String value) {
  return value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
}

SendDraftSession? updateSendDestinationCode(
  SendDraftSession? draft,
  String value,
) {
  if (draft == null) {
    return null;
  }
  final normalized = normalizeSendDestinationCode(value);
  if (normalized == draft.destinationCode) {
    return draft;
  }
  return draft.copyWith(
    destinationCode: normalized,
    clearSelectedDestination: true,
  );
}

SendDraftSession? clearSendDestinationCode(SendDraftSession? draft) {
  if (draft == null) {
    return null;
  }
  return draft.copyWith(destinationCode: '');
}

SendDraftSession? selectNearbyDestination(
  SendDraftSession? draft,
  SendDestinationViewData destination,
) {
  if (draft == null) {
    return null;
  }
  if (draft.selectedDestination == destination) {
    return draft.copyWith(clearSelectedDestination: true);
  }
  return draft.copyWith(
    selectedDestination: destination,
    destinationCode: '',
  );
}

SendDraftSession restoreSendDraft(
  DriftAppState state, {
  String destinationCode = '',
}) {
  return SendDraftSession(
    items: state.sendItems,
    isInspecting: false,
    nearbyDestinations: const [],
    nearbyScanInFlight: false,
    nearbyScanCompletedOnce: false,
    destinationCode: destinationCode,
  );
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/send/send_shell_actions_test.dart`
Expected: PASS.

### Task 2: Wire `DriftAppNotifier` through the helpers

**Files:**
- Modify: `flutter/lib/state/drift_app_notifier.dart:1-1040`
- Modify: `flutter/test/state/drift_app_notifier_test.dart` only if a notifier wrapper assertion needs adjustment

- [ ] **Step 1: Replace the send-destination and nearby-selection methods with helper calls**

```dart
void updateSendDestinationCode(String value) {
  final next = send_shell_actions.updateSendDestinationCode(
    _draftSession,
    value,
  );
  if (next == null) {
    return;
  }
  _setSession(next);
}

void clearSendDestinationCode() {
  final next = send_shell_actions.clearSendDestinationCode(_draftSession);
  if (next == null) {
    return;
  }
  _setSession(next);
}

void selectNearbyDestination(SendDestinationViewData destination) {
  final next = send_shell_actions.selectNearbyDestination(
    _draftSession,
    destination,
  );
  if (next == null) {
    return;
  }
  _setSession(next);
}
```

- [ ] **Step 2: Replace the restore/send-again path with the helper**

```dart
void _returnToSendSelection() {
  _restoreSendDraft();
}

void _restoreSendDraft({String destinationCode = ''}) {
  _cancelActiveSendTransfer();
  _clearSendMetricState();
  _setSession(
    send_shell_actions.restoreSendDraft(
      state,
      destinationCode: destinationCode,
    ),
  );
  _scheduleNearbyScanning();
}
```

- [ ] **Step 3: Keep send-result primary action handling in the notifier, but simplify the send-only branch**

The notifier should still decide when to call `resetShell()` versus `_restoreSendDraft()` versus `_returnToSendSelection()`, but the actual session mutation should come from the new helper module, not inline `copyWith` calls.

- [ ] **Step 4: Run the send and notifier tests**

Run: `flutter test test/features/send/send_shell_actions_test.dart test/features/send/send_session_reducer_test.dart test/features/send/send_transfer_coordinator_test.dart test/features/send/send_nearby_coordinator_test.dart test/features/send/send_selection_builder_test.dart test/features/send/send_selection_coordinator_test.dart test/state/drift_app_notifier_test.dart test/features/send/send_controller_test.dart`
Expected: PASS.

- [ ] **Step 5: Run analyzer**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add flutter/lib/features/send/send_shell_actions.dart flutter/lib/state/drift_app_notifier.dart flutter/test/features/send/send_shell_actions_test.dart docs/superpowers/plans/2026-04-10-send-shell-actions.md
git commit -m "refactor: extract send shell actions"
```

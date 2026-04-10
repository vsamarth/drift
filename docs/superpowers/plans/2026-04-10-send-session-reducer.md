# Send Session Reducer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the send transfer update-to-session mapping out of `DriftAppNotifier` into a pure reducer so send state transitions can be tested and evolved independently.

**Architecture:** Add a small reducer module under `flutter/lib/features/send/` that accepts the current app state, a `SendTransferUpdate`, and the current send payload start timestamp, then returns the next shell session object. Keep `DriftAppNotifier` responsible for the mutable Riverpod state and the send payload timer, but make `_applySendUpdate` a thin wrapper around the reducer. Add focused tests for the reducer and keep the existing notifier and send controller tests as the integration safety net.

**Tech Stack:** Dart 3, Flutter, Riverpod, `flutter_test`

---

### Task 1: Add the pure send session reducer and its unit test

**Files:**
- Create: `flutter/lib/features/send/send_session_reducer.dart`
- Create: `flutter/test/features/send/send_session_reducer_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:drift_app/core/models/transfer_models.dart';
import 'package:drift_app/features/send/send_session_reducer.dart';
import 'package:drift_app/platform/send_transfer_source.dart';
import 'package:drift_app/state/app_identity.dart';
import 'package:drift_app/state/drift_app_state.dart';
import 'package:drift_app/state/receiver_service_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('connecting update becomes a send transfer session', () {
    final state = DriftAppState(
      identity: const DriftAppIdentity(
        deviceName: 'Drift Device',
        deviceType: 'laptop',
        downloadRoot: '/tmp/Downloads',
      ),
      receiverBadge: const ReceiverBadgeState(
        code: 'F9P2Q1',
        status: 'Ready',
        phase: ReceiverBadgePhase.ready,
      ),
      session: const SendDraftSession(
        items: [
          TransferItemViewData(
            name: 'sample.txt',
            path: 'sample.txt',
            size: '18 KB',
            kind: TransferItemKind.file,
          ),
        ],
        isInspecting: false,
        nearbyDestinations: [],
        nearbyScanInFlight: false,
        nearbyScanCompletedOnce: false,
        destinationCode: 'AB2CD3',
      ),
      animateSendingConnection: false,
    );

    final session = reduceSendTransferUpdate(
      state: state,
      update: const SendTransferUpdate(
        phase: SendTransferUpdatePhase.connecting,
        destinationLabel: 'Maya\'s iPhone',
        statusMessage: 'Connecting...',
        itemCount: 1,
        totalSize: '18 KB',
        bytesSent: 0,
        totalBytes: 18 * 1024,
      ),
      payloadStartedAt: null,
    );

    expect(session, isA<SendTransferSession>());
    expect((session as SendTransferSession).phase,
        SendTransferSessionPhase.connecting);
    expect(session.summary.destinationLabel, 'Maya\'s iPhone');
  });
}
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `flutter test test/features/send/send_session_reducer_test.dart`
Expected: fail because `reduceSendTransferUpdate` does not exist yet.

- [ ] **Step 3: Implement the reducer**

```dart
import '../../core/models/transfer_models.dart';
import '../../state/drift_app_state.dart';
import '../../state/drift_sample_data.dart';
import '../../shared/formatting/transfer_message_format.dart';
import '../../platform/send_transfer_source.dart';
import 'send_mapper.dart' as send_mapper;

ShellSessionState reduceSendTransferUpdate({
  required DriftAppState state,
  required SendTransferUpdate update,
  required DateTime? payloadStartedAt,
}) {
  final items = state.sendItems.isEmpty ? sampleSendItems : state.sendItems;
  final existingSummary = state.sendSummary ?? sampleSendSummary;
  final summary = existingSummary.copyWith(
    itemCount: update.itemCount,
    totalSize: update.totalSize,
    code: state.sendDestinationCode,
    destinationLabel: update.destinationLabel,
    statusMessage: update.errorMessage ?? update.statusMessage,
  );
  final progress = progressFromSnapshot(update.snapshot);
  final bytesTransferred =
      progress.bytesTransferred ?? (update.bytesSent > 0 ? update.bytesSent : null);

  return switch (update.phase) {
    SendTransferUpdatePhase.connecting => SendTransferSession(
      phase: SendTransferSessionPhase.connecting,
      items: items,
      summary: summary,
      plan: update.plan ?? state.sendTransferPlan,
      snapshot: update.snapshot,
      remoteDeviceType: update.remoteDeviceType,
    ),
    SendTransferUpdatePhase.waitingForDecision => SendTransferSession(
      phase: SendTransferSessionPhase.waitingForDecision,
      items: items,
      summary: summary,
      plan: update.plan ?? state.sendTransferPlan,
      snapshot: update.snapshot,
      remoteDeviceType: update.remoteDeviceType,
    ),
    SendTransferUpdatePhase.accepted => SendTransferSession(
      phase: SendTransferSessionPhase.accepted,
      items: items,
      summary: summary,
      plan: update.plan ?? state.sendTransferPlan,
      snapshot: update.snapshot,
      remoteDeviceType: update.remoteDeviceType,
    ),
    SendTransferUpdatePhase.declined => SendResultSession(
      success: false,
      outcome: TransferResultOutcomeData.declined,
      items: items,
      summary: summary.copyWith(
        statusMessage: update.errorMessage ?? 'Transfer declined.',
      ),
      plan: update.plan ?? state.sendTransferPlan,
      snapshot: update.snapshot,
      remoteDeviceType: update.remoteDeviceType,
    ),
    SendTransferUpdatePhase.sending => SendTransferSession(
      phase: SendTransferSessionPhase.sending,
      items: items,
      summary: summary,
      plan: update.plan ?? state.sendTransferPlan,
      snapshot: update.snapshot,
      remoteDeviceType: update.remoteDeviceType,
      payloadBytesSent: bytesTransferred,
      payloadTotalBytes:
          progress.totalBytes ?? (update.totalBytes > 0 ? update.totalBytes : null),
      payloadSpeedLabel: progress.speedLabel,
      payloadEtaLabel: progress.etaLabel,
    ),
    SendTransferUpdatePhase.completed => SendResultSession(
      success: true,
      outcome: TransferResultOutcomeData.success,
      items: items,
      summary: summary,
      metrics: send_mapper.buildSendCompletionMetrics(
        update,
        payloadStartedAt: payloadStartedAt,
      ),
      plan: update.plan ?? state.sendTransferPlan,
      snapshot: update.snapshot,
      remoteDeviceType: update.remoteDeviceType,
    ),
    SendTransferUpdatePhase.cancelled => SendResultSession(
      success: false,
      outcome: TransferResultOutcomeData.cancelled,
      items: items,
      summary: summary.copyWith(
        statusMessage: update.errorMessage ?? 'Transfer cancelled.',
      ),
      plan: update.plan ?? state.sendTransferPlan,
      snapshot: update.snapshot,
      remoteDeviceType: update.remoteDeviceType,
    ),
    SendTransferUpdatePhase.failed => SendResultSession(
      success: false,
      outcome: TransferResultOutcomeData.failed,
      items: items,
      summary: summary,
      plan: update.plan ?? state.sendTransferPlan,
      snapshot: update.snapshot,
      remoteDeviceType: update.remoteDeviceType,
    ),
  };
}
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `flutter test test/features/send/send_session_reducer_test.dart`
Expected: PASS.

### Task 2: Wire `DriftAppNotifier` to the reducer

**Files:**
- Modify: `flutter/lib/state/drift_app_notifier.dart:1-1160`
- Modify: `flutter/test/state/drift_app_notifier_test.dart` only if the notifier wrapper needs a test adjustment

- [ ] **Step 1: Replace `_applySendUpdate` with a reducer call**

```dart
void _applySendUpdate(SendTransferUpdate update) {
  final progress = progressFromSnapshot(update.snapshot);
  final bytesTransferred =
      progress.bytesTransferred ?? (update.bytesSent > 0 ? update.bytesSent : null);
  if (_sendPayloadStartedAt == null && (bytesTransferred ?? 0) > 0) {
    _sendPayloadStartedAt = DateTime.now();
  }

  final nextSession = reduceSendTransferUpdate(
    state: state,
    update: update,
    payloadStartedAt: _sendPayloadStartedAt,
  );
  _setSession(nextSession);
}
```

- [ ] **Step 2: Remove any leftover duplicated send-session mapping code**

Delete the old `switch (update.phase)` block from `_applySendUpdate` after the reducer is in place, and keep the payload-start timestamp update in the notifier for now.

- [ ] **Step 3: Run the existing send and notifier tests**

Run: `flutter test test/features/send/send_session_reducer_test.dart test/features/send/send_transfer_coordinator_test.dart test/features/send/send_nearby_coordinator_test.dart test/features/send/send_selection_builder_test.dart test/features/send/send_selection_coordinator_test.dart test/state/drift_app_notifier_test.dart test/features/send/send_controller_test.dart`
Expected: PASS.

- [ ] **Step 4: Run analyzer**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add flutter/lib/features/send/send_session_reducer.dart flutter/lib/state/drift_app_notifier.dart flutter/test/features/send/send_session_reducer_test.dart
git commit -m "refactor: extract send session reducer"
```

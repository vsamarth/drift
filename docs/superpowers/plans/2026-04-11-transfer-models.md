# Transfer Models Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce clean, protocol-shaped transfer models in `app/` so incoming offers can carry identity and manifest data without coupling the UI to raw Rust event shapes.

**Architecture:** `transfers` will own an immutable identity model that mirrors `crates/core/src/protocol/message.rs`, plus a dedicated manifest model and a session state object that composes them. The service layer will map Rust receiver events into these models, while the presentation layer reads only the normalized Dart types.

**Tech Stack:** Flutter, Riverpod, flutter_riverpod, flutter_test, flutter_rust_bridge-generated API types.

---

### Task 1: Add protocol-shaped transfer models

**Files:**
- Create: `app/lib/features/transfers/application/identity.dart`
- Create: `app/lib/features/transfers/application/manifest.dart`
- Modify: `app/lib/features/transfers/application/state.dart`
- Test: `app/test/features/transfers/state_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/transfers/feature.dart';

void main() {
  test('transfer identity trims display name and keeps protocol fields', () {
    const identity = TransferIdentity(
      role: TransferRole.sender,
      endpointId: 'endpoint-1',
      deviceName: ' Maya ',
      deviceType: DeviceType.laptop,
    );

    expect(identity.displayName, 'Maya');
    expect(identity.endpointId, 'endpoint-1');
    expect(identity.role, TransferRole.sender);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test app/test/features/transfers/state_test.dart -r compact`
Expected: FAIL because `TransferIdentity` is not defined yet.

- [ ] **Step 3: Write minimal implementation**

```dart
@immutable
class TransferIdentity { ... }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test app/test/features/transfers/state_test.dart -r compact`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/transfers/application/identity.dart app/lib/features/transfers/application/manifest.dart app/lib/features/transfers/application/state.dart app/test/features/transfers/state_test.dart
git commit -m "feat: add transfer identity models"
```

### Task 2: Map transfer events into the new models

**Files:**
- Modify: `app/lib/features/transfers/application/service.dart`
- Modify: `app/lib/platform/rust/receiver/fake_source.dart`
- Modify: `app/lib/platform/rust/receiver/source.dart`
- Modify: `app/lib/features/transfers/application/controller.dart`
- Modify: `app/lib/features/transfers/feature.dart`
- Modify: `app/test/features/transfers/service_test.dart`
- Modify: `app/test/features/transfers/feature_test.dart`
- Modify: `app/test/platform/rust/receiver/fake_receiver_service_source_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
test('incoming offer captures identity and manifest items', () async {
  final source = FakeReceiverServiceSource();
  final container = ProviderContainer(
    overrides: [transfersServiceSourceProvider.overrideWithValue(source)],
  );
  addTearDown(container.dispose);

  source.emitIncomingOffer(
    senderName: 'Maya',
    senderEndpointId: 'endpoint-1',
    senderDeviceType: DeviceType.laptop,
    destinationLabel: 'Downloads',
    saveRootLabel: 'Downloads',
    items: const [
      TransferManifestItem(path: 'report.pdf', sizeBytes: 1024),
    ],
  );

  await Future<void>.delayed(Duration.zero);

  final state = container.read(transfersServiceProvider);
  expect(state.offer?.sender.endpointId, 'endpoint-1');
  expect(state.offer?.manifest.itemCount, 1);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test app/test/features/transfers/service_test.dart -r compact`
Expected: FAIL because the service still only maps sender names.

- [ ] **Step 3: Write minimal implementation**

```dart
// Map rust_receiver.ReceiverTransferEvent into TransferIncomingOffer and
// TransferSessionState, keeping the manifest on the offer.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test app/test/features/transfers/service_test.dart app/test/features/transfers/feature_test.dart app/test/platform/rust/receiver/fake_receiver_service_source_test.dart -r compact`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/transfers/application/service.dart app/lib/platform/rust/receiver/fake_source.dart app/lib/platform/rust/receiver/source.dart app/lib/features/transfers/application/controller.dart app/lib/features/transfers/feature.dart app/test/features/transfers/service_test.dart app/test/features/transfers/feature_test.dart app/test/platform/rust/receiver/fake_receiver_service_source_test.dart
git commit -m "feat: map transfer offers to clean models"
```

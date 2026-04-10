# Send Selection Extraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the send draft item-merging and pending-item construction logic out of `DriftAppNotifier` into a small send-feature helper.

**Architecture:** Introduce a pure helper in `flutter/lib/features/send/` that normalizes dropped or picked paths into `TransferItemViewData` and merges new pending items into an existing send selection. Keep the notifier responsible for session mutation and side effects for now, but delegate the selection-shaping logic to the helper so the next refactor slice has a smaller target.

**Tech Stack:** Flutter, Dart, Riverpod, `flutter_test`.

---

### Task 1: Add a send-selection helper and tests

**Files:**
- Create: `flutter/lib/features/send/send_selection_builder.dart`
- Create: `flutter/test/features/send/send_selection_builder_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:drift_app/core/models/transfer_models.dart';
import 'package:drift_app/features/send/send_selection_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds a pending folder item from a trailing slash path', () {
    final builder = SendSelectionBuilder();

    final item = builder.pendingItemForPath('photos/');

    expect(item.name, 'photos');
    expect(item.path, 'photos/');
    expect(item.size, 'Adding...');
    expect(item.kind, TransferItemKind.folder);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/send/send_selection_builder_test.dart`
Expected: fail because `SendSelectionBuilder` does not exist yet.

- [ ] **Step 3: Write minimal implementation**

```dart
import '../../core/models/transfer_models.dart';

class SendSelectionBuilder {
  const SendSelectionBuilder();

  TransferItemViewData pendingItemForPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final trimmed = normalized.endsWith('/')
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
    final segments = trimmed.split('/')
      ..removeWhere((segment) => segment.isEmpty);
    final name = segments.isEmpty ? trimmed : segments.last;
    final isFolder = normalized.endsWith('/');

    return TransferItemViewData(
      name: name.isEmpty ? path : name,
      path: path,
      size: 'Adding...',
      kind: isFolder ? TransferItemKind.folder : TransferItemKind.file,
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/send/send_selection_builder_test.dart`
Expected: PASS

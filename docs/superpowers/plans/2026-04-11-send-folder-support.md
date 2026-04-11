# Send Folder Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the send flow accept folders through the existing `Select Files` entry point and drag-and-drop, then render folders distinctly in the preview.

**Architecture:** Keep the current home shell and preview route structure. Add a small chooser sheet behind `Select Files` with `Files` and `Folder` actions, normalize both file and folder picks into the same `SendPickedFile` model, and teach the preview to render directory rows with a folder icon and empty size column. Use a small picker abstraction so the shell can be tested without talking to the platform file dialogs directly. Make the preview summary item-neutral so folders are not mislabeled as files.

**Tech Stack:** Flutter, `file_selector`, `desktop_drop`, `go_router`, `flutter_riverpod`

---

### Task 1: Make send items directory-aware

**Files:**
- Modify: `app/lib/features/send/application/model.dart`
- Create: `app/lib/features/send/application/send_selection_picker.dart`
- Test: `app/test/features/send/application/model_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
test('SendPickedFile.fromPath marks files and directories correctly', () async {
  final file = File('${Directory.systemTemp.path}/drift-send-file.txt');
  await file.writeAsString('hello');
  final dir = await Directory.systemTemp.createTemp('drift-send-dir');

  final pickedFile = SendPickedFile.fromPath(file.path);
  final pickedDir = SendPickedFile.fromPath(dir.path);

  expect(pickedFile.kind, SendPickedFileKind.file);
  expect(pickedFile.sizeBytes, isNull);
  expect(pickedDir.kind, SendPickedFileKind.directory);
  expect(pickedDir.sizeBytes, isNull);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/send/application/model_test.dart`
Expected: FAIL because `SendPickedFileKind` and directory classification do not exist yet.

- [ ] **Step 3: Write the minimal implementation**

Add a `SendPickedFileKind` enum and extend `SendPickedFile` so it can represent both files and directories:

```dart
import 'dart:io';

enum SendPickedFileKind { file, directory }

@immutable
class SendPickedFile {
  const SendPickedFile({
    required this.path,
    required this.name,
    required this.kind,
    this.sizeBytes,
  });

  factory SendPickedFile.fromPath(String path) {
    final type = FileSystemEntity.typeSync(path);
    final isDirectory = type == FileSystemEntityType.directory;
    final uri = Uri.file(path);
    final name = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : path;
    return SendPickedFile(
      path: path,
      name: name.trim().isEmpty ? path : name,
      kind: isDirectory ? SendPickedFileKind.directory : SendPickedFileKind.file,
    );
  }

  final String path;
  final String name;
  final SendPickedFileKind kind;
  final BigInt? sizeBytes;
}
```

Add a small picker abstraction so the shell can ask for files or folders without talking to `file_selector` directly:

```dart
abstract class SendSelectionPicker {
  Future<List<SendPickedFile>> pickFiles();
  Future<List<SendPickedFile>> pickFolder();
}
```

Use the existing `file_selector` package inside a `FileSelectorSendSelectionPicker` implementation.

`pickFiles()` should still read file sizes from `XFile.length()` so the preview keeps showing sizes for files, while `pickFolder()` should return one directory item with `sizeBytes == null`.

Expose the picker with a provider so `DriftShell` can read it and tests can override it:

```dart
final sendSelectionPickerProvider = Provider<SendSelectionPicker>((ref) {
  return FileSelectorSendSelectionPicker();
});
```

The implementation should look like this:

```dart
class FileSelectorSendSelectionPicker implements SendSelectionPicker {
  @override
  Future<List<SendPickedFile>> pickFiles() async {
    final pickedFiles = await openFiles();
    return Future.wait(
      pickedFiles.map((file) async {
        final path = file.path.isNotEmpty ? file.path : file.name;
        final name = file.name.trim().isEmpty
            ? Uri.file(path).pathSegments.isNotEmpty
                ? Uri.file(path).pathSegments.last
                : path
            : file.name;
        BigInt? sizeBytes;
        try {
          sizeBytes = BigInt.from(await file.length());
        } catch (_) {
          sizeBytes = null;
        }
        return SendPickedFile(
          path: path,
          name: name,
          kind: SendPickedFileKind.file,
          sizeBytes: sizeBytes,
        );
      }),
    );
  }

  @override
  Future<List<SendPickedFile>> pickFolder() async {
    final path = await getDirectoryPath();
    if (path == null || path.isEmpty) {
      return const [];
    }

    return [
      SendPickedFile(
        path: path,
        name: SendPickedFile.fromPath(path).name,
        kind: SendPickedFileKind.directory,
      ),
    ];
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/send/application/model_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/send/application/model.dart \
  app/lib/features/send/application/send_selection_picker.dart \
  app/test/features/send/application/model_test.dart
git commit -m "feat: support directory-aware send items"
```

### Task 2: Add the Files/Folder chooser and wire it into the shell

**Files:**
- Create: `app/lib/features/send/presentation/send_selection_source_sheet.dart`
- Modify: `app/lib/shell/drift_shell.dart`
- Test: `app/test/features/send/presentation/send_selection_source_sheet_test.dart`
- Test: `app/test/shell/drift_shell_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
testWidgets('chooser sheet offers files and folder actions', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            await showModalBottomSheet<void>(
              context: context,
              builder: (_) => SendSelectionSourceSheet(
                onChooseFiles: () async {},
                onChooseFolder: () async {},
              ),
            );
          },
          child: const Text('Open chooser'),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Open chooser'));
  await tester.pumpAndSettle();

  expect(find.text('Files'), findsOneWidget);
  expect(find.text('Folder'), findsOneWidget);
});
```

Also add a shell test that overrides `sendSelectionPickerProvider` with a fake picker, taps `Select files`, chooses `Folder`, and expects a directory row in `SendDraftPreview`.

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
flutter test test/features/send/presentation/send_selection_source_sheet_test.dart
flutter test test/shell/drift_shell_test.dart
```

Expected: the new chooser test fails because the sheet does not exist yet, and the shell test fails because the shell does not open a chooser or use a picker abstraction yet.

- [ ] **Step 3: Write the minimal implementation**

Create a lightweight sheet widget that closes itself before invoking the chosen action:

```dart
class SendSelectionSourceSheet extends StatelessWidget {
  const SendSelectionSourceSheet({
    super.key,
    required this.onChooseFiles,
    required this.onChooseFolder,
  });

  final Future<void> Function() onChooseFiles;
  final Future<void> Function() onChooseFolder;
  ...
}
```

Wire `DriftShell` so tapping `Select files` opens the sheet, and the two actions call the picker abstraction:

```dart
final picker = ref.watch(sendSelectionPickerProvider);

Future<void> _showSelectionSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    builder: (_) => SendSelectionSourceSheet(
      onChooseFiles: () async {
        final files = await picker.pickFiles();
        if (files.isNotEmpty && context.mounted) {
          context.goSendDraft(files: files);
        }
      },
      onChooseFolder: () async {
        final folders = await picker.pickFolder();
        if (folders.isNotEmpty && context.mounted) {
          context.goSendDraft(files: folders);
        }
      },
    ),
  );
}
```

Keep the `Select files` label unchanged in `SendDropZoneSurface`; only the callback behind it changes.

Inside `SendSelectionSourceSheet`, each tap handler should dismiss the sheet before calling the callback:

```dart
TextButton(
  onPressed: () {
    Navigator.of(context).pop();
    unawaited(onChooseFiles());
  },
  child: const Text('Files'),
)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
flutter test test/features/send/presentation/send_selection_source_sheet_test.dart
flutter test test/shell/drift_shell_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/send/presentation/send_selection_source_sheet.dart \
  app/lib/shell/drift_shell.dart \
  app/lib/features/send/send_drop_zone.dart \
  app/test/features/send/presentation/send_selection_source_sheet_test.dart \
  app/test/shell/drift_shell_test.dart
git commit -m "feat: add send folder chooser"
```

### Task 3: Render directories distinctly in the draft preview

**Files:**
- Modify: `app/lib/features/send/presentation/send_draft_preview.dart`
- Test: `app/test/features/send/presentation/send_draft_preview_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
testWidgets('renders directories with a folder icon and blank size', (
  tester,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: SendDraftPreview(
        files: [
          SendPickedFile(
            path: '/tmp/report.pdf',
            name: 'report.pdf',
            kind: SendPickedFileKind.file,
            sizeBytes: BigInt.from(1024),
          ),
          SendPickedFile(
            path: '/tmp/photos',
            name: 'photos',
            kind: SendPickedFileKind.directory,
          ),
        ],
      ),
    ),
  );

  expect(find.byIcon(Icons.folder_rounded), findsOneWidget);
  expect(find.text('report.pdf'), findsOneWidget);
  expect(find.text('photos'), findsOneWidget);
  expect(find.text('1.0 KB'), findsOneWidget);
  expect(find.text('2 items ready'), findsOneWidget);
});
```

Add a second assertion that the directory row leaves the size cell empty rather than showing a dash or a byte value.

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/send/presentation/send_draft_preview_test.dart`
Expected: FAIL because `SendDraftPreview` still renders file-only rows.

- [ ] **Step 3: Write the minimal implementation**

Teach the preview row to branch on `SendPickedFile.kind`:

```dart
final icon = file.kind == SendPickedFileKind.directory
    ? Icons.folder_rounded
    : Icons.description_outlined;

final sizeLabel = file.kind == SendPickedFileKind.directory
    ? ''
    : file.sizeBytes == null
        ? ''
        : formatBytes(file.sizeBytes!);
```

Keep the current table layout, but render the size column as empty for directories.

Update the summary label to be item-neutral:

```dart
String _selectionSummaryLabel(List<SendPickedFile> files) {
  final count = files.length;
  if (count == 0) {
    return 'No items ready';
  }

  return count == 1 ? '1 item ready' : '$count items ready';
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/send/presentation/send_draft_preview_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/send/presentation/send_draft_preview.dart \
  app/test/features/send/presentation/send_draft_preview_test.dart
git commit -m "feat: render directories in send preview"
```

### Task 4: Verify the full send flow

**Files:**
- Test: `app/test/shell/drift_shell_test.dart`
- Test: `app/test/features/send/presentation/send_draft_preview_test.dart`

- [ ] **Step 1: Write the final flow checks**

Add coverage for:

```dart
testWidgets('dropping a directory navigates to preview', (tester) async {
  final dir = await Directory.systemTemp.createTemp('drift-send-dir');
  ...
  dropZone.onDropPaths([dir.path]);
  ...
  expect(find.byIcon(Icons.folder_rounded), findsOneWidget);
  expect(find.text(dir.path.split(Platform.pathSeparator).last), findsOneWidget);
});
```

and:

```dart
testWidgets('choosing Folder from the sheet routes to preview', (tester) async {
  final fakePicker = FakeSendSelectionPicker(
    folderResult: [
      SendPickedFile(
        path: '/tmp/photos',
        name: 'photos',
        kind: SendPickedFileKind.directory,
      ),
    ],
  );
  ...
});
```

- [ ] **Step 2: Run the focused tests**

Run:

```bash
flutter test test/shell/drift_shell_test.dart test/features/send/presentation/send_draft_preview_test.dart
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add app/test/shell/drift_shell_test.dart \
  app/test/features/send/presentation/send_draft_preview_test.dart
git commit -m "test: cover folder send flow"
```

## Self-Review

- Spec coverage: the chooser sheet, picker abstraction, dropped folder handling, and preview rendering all map to a task.
- Placeholder scan: no TBDs or TODOs remain.
- Type consistency: `SendPickedFile`, `SendPickedFileKind`, `SendSelectionPicker`, and `SendSelectionSourceSheet` are used consistently across tasks.
- Scope check: this stays within the send flow and does not introduce transfer backend changes.

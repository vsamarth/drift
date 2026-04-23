# V0.2.0 Idle Screen Restoration Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore the idle screen visuals and layout to the v0.2.0 style (card-based, scrollable list).

**Architecture:** Replaces the Ambient "Stack" layout with a `CustomScrollView` containing discrete card widgets for Identity and File Selection.

**Tech Stack:** Flutter, Riverpod.

---

### Task 1: Restore Identity Card (v0.2.0 Style)

**Files:**
- Create: `flutter/lib/shell/widgets/v02_identity_card.dart`

- [ ] **Step 1: Write the V02IdentityCard implementation**
Adapted from v0.2.0 `MobileIdentityCard`. Uses current `ReceiverIdleViewState`.

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../features/receive/application/state.dart';
import '../../../theme/drift_theme.dart';

class V02IdentityCard extends StatefulWidget {
  const V02IdentityCard({super.key, required this.state});

  final ReceiverIdleViewState state;

  @override
  State<V02IdentityCard> createState() => _V02IdentityCardState();
}

class _V02IdentityCardState extends State<V02IdentityCard> {
  bool _copied = false;
  Timer? _timer;

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.state.clipboardCode));
    _timer?.cancel();
    HapticFeedback.mediumImpact();
    setState(() => _copied = true);
    _timer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatCode(String code) {
    if (code.length != 6) return code;
    return '${code.substring(0, 3)} ${code.substring(3)}';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: kSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: const BorderSide(color: kBorder, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.state.deviceName,
                  style: driftSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: kInk,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: widget.state.badge.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.state.badge.label,
                      style: driftSans(
                        fontSize: 14,
                        color: widget.state.badge.color,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 32),
            Text(
              'RECEIVE CODE',
              style: driftSans(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: kMuted,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _copy,
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  Text(
                    _formatCode(widget.state.code),
                    style: driftMono(
                      fontSize: 36,
                      fontWeight: FontWeight.w700,
                      color: kInk,
                      letterSpacing: 4,
                    ),
                  ),
                  const SizedBox(width: 12),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _copied
                        ? const Icon(
                            Icons.check_circle_outline_rounded,
                            color: Color(0xFF49B36C),
                            key: ValueKey('done'),
                          )
                        : Icon(
                            Icons.copy_rounded,
                            color: kMuted.withValues(alpha: 0.5),
                            key: const ValueKey('copy'),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

### Task 2: Restore Select Files Card (v0.2.0 Style)

**Files:**
- Create: `flutter/lib/shell/widgets/v02_select_files_card.dart`

- [ ] **Step 1: Write the V02SelectFilesCard implementation**
Direct restoration from v0.2.0.

```dart
import 'package:flutter/material.dart';
import '../../../theme/drift_theme.dart';

class V02SelectFilesCard extends StatelessWidget {
  final VoidCallback? onTap;

  const V02SelectFilesCard({
    super.key,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: kBorder),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.add_rounded, color: kInk, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Select files',
                    style: driftSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: kInk,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tap to choose files to send.',
                    style: driftSans(fontSize: 14, color: kMuted, height: 1.3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

### Task 3: Revert MobileShell Layout to v0.2.0

**Files:**
- Modify: `flutter/lib/shell/mobile_shell.dart`

- [ ] **Step 1: Replace Stack layout with CustomScrollView**
Restores the scrollable card list structure.

```dart
// ... existing imports ...
import 'widgets/v02_identity_card.dart';
import 'widgets/v02_select_files_card.dart';

// ... in MobileShell build ...
    return ReceiveTransferRouteGate(
      child: Scaffold(
        backgroundColor: kBg,
        body: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      const Spacer(),
                      IconButton(
                        onPressed: () => context.goSettings(),
                        icon: const Icon(Icons.tune_rounded),
                        tooltip: 'Settings',
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const SizedBox(height: 8),
                  V02IdentityCard(state: receiverState),
                  const SizedBox(height: 32),
                  V02SelectFilesCard(
                    onTap: () {
                      showSendSelectionSourceSheet(
                        context,
                        onChooseFiles: () => pickFiles(context, ref),
                        onChooseFolder: () => pickFolder(context, ref),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
```

### Task 4: Cleanup Ambient Components

- [ ] **Step 1: Delete ambient widgets**
Run: `rm flutter/lib/shell/widgets/ambient_background.dart flutter/lib/shell/widgets/identity_header.dart flutter/lib/shell/widgets/hero_code.dart flutter/lib/shell/widgets/integrated_send_button.dart`

- [ ] **Step 2: Update widget_test.dart**
Revert the test to use `pumpAndSettle()` since the infinite animation is gone.

```dart
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAppSettingsProvider.overrideWithValue(testAppSettings),
        ],
        child: const DriftApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Select files'), findsOneWidget);
```

- [ ] **Step 3: Run flutter analyze and tests**
Run: `cd flutter && flutter analyze && flutter test`
Expected: PASS

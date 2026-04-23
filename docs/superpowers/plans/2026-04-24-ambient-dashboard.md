# Ambient Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the boxy, card-based mobile home page with a clean "Ambient Canvas" that uses breathing animations, large-scale typography, and integrated actions.

**Architecture:** A layered `Stack` approach where a background animation layer is separated from the interactive UI components (Header, Hero Code, Footer Button).

**Tech Stack:** Flutter, Riverpod (for state), Material 3.

---

### Task 1: Create AmbientBackground Widget

**Files:**
- Create: `flutter/lib/shell/widgets/ambient_background.dart`

- [ ] **Step 1: Write the AmbientBackground implementation**
Create a widget that uses an `AnimationController` to cycle opacity and scale of radial gradients.

```dart
import 'package:flutter/material.dart';
import '../../theme/drift_theme.dart';

class AmbientBackground extends StatefulWidget {
  const AmbientBackground({super.key});

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          children: [
            Positioned(
              top: -100,
              right: -50,
              child: _GradientBlob(
                color: kAccentCyan.withValues(alpha: 0.05 + (_controller.value * 0.03)),
                scale: 1.0 + (_controller.value * 0.2),
              ),
            ),
            Positioned(
              bottom: 100,
              left: -80,
              child: _GradientBlob(
                color: kAccentWarm.withValues(alpha: 0.04 + (_controller.value * 0.04)),
                scale: 1.2 + (_controller.value * 0.1),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _GradientBlob extends StatelessWidget {
  const _GradientBlob({required this.color, required this.scale});
  final Color color;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: scale,
      child: Container(
        width: 400,
        height: 400,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}
```

### Task 2: Create IdentityHeader Widget

**Files:**
- Create: `flutter/lib/shell/widgets/identity_header.dart`

- [ ] **Step 1: Write the IdentityHeader implementation**
A clean row showing device name and status.

```dart
import 'package:flutter/material.dart';
import '../../features/receive/application/state.dart';
import '../../theme/drift_theme.dart';

class IdentityHeader extends StatelessWidget {
  const IdentityHeader({super.key, required this.state, this.onOpenSettings});

  final ReceiverIdleViewState state;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                state.deviceName,
                style: driftSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: kInk,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: state.badge.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    state.badge.label,
                    style: driftSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: state.badge.color,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onOpenSettings,
          icon: const Icon(Icons.tune_rounded, size: 20),
          style: IconButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: kMuted,
          ),
        ),
      ],
    );
  }
}
```

### Task 3: Create HeroCode Widget

**Files:**
- Create: `flutter/lib/shell/widgets/hero_code.dart`

- [ ] **Step 1: Write HeroCode implementation**
The large central code with "Copied" feedback.

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/drift_theme.dart';

class HeroCode extends StatefulWidget {
  const HeroCode({super.key, required this.code, required this.clipboardCode});
  final String code;
  final String clipboardCode;

  @override
  State<HeroCode> createState() => _HeroCodeState();
}

class _HeroCodeState extends State<HeroCode> {
  bool _copied = false;
  Timer? _timer;

  void _onCopy() async {
    await Clipboard.setData(ClipboardData(text: widget.clipboardCode));
    await HapticFeedback.mediumImpact();
    setState(() => _copied = true);
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final codeStr = widget.code;
    final displayCode = codeStr.length == 6 
        ? '${codeStr.substring(0, 3)}  ${codeStr.substring(3)}' 
        : codeStr;

    return GestureDetector(
      onTap: _onCopy,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              _copied ? 'Copied to clipboard' : 'Tap to copy',
              key: ValueKey(_copied),
              style: driftSans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _copied ? const Color(0xFF5E9B70) : kMuted.withValues(alpha: 0.5),
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 16),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              displayCode,
              style: driftMono(
                fontSize: 72,
                fontWeight: FontWeight.w800,
                color: kInk,
                letterSpacing: 4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

### Task 4: Create IntegratedSendButton Widget

**Files:**
- Create: `flutter/lib/shell/widgets/integrated_send_button.dart`

- [ ] **Step 1: Write IntegratedSendButton implementation**
The bottom anchored pill button.

```dart
import 'package:flutter/material.dart';
import '../../theme/drift_theme.dart';

class IntegratedSendButton extends StatelessWidget {
  const IntegratedSendButton({super.key, required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.add_rounded, size: 20),
        label: const Text('Send Files or Folders'),
        style: FilledButton.styleFrom(
          backgroundColor: kInk,
          foregroundColor: kSurface,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          textStyle: driftSans(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
      ),
    );
  }
}
```

### Task 5: Update MobileShell Layout

**Files:**
- Modify: `flutter/lib/shell/mobile_shell.dart`

- [ ] **Step 1: Replace MobileIdleHub with the new Ambient Canvas**
Update the build method to use a `Stack` with the new components.

```dart
// ... existing imports ...
import 'widgets/ambient_background.dart';
import 'widgets/identity_header.dart';
import 'widgets/hero_code.dart';
import 'widgets/integrated_send_button.dart';

// ... in MobileShell build ...
    return ReceiveTransferRouteGate(
      child: Scaffold(
        backgroundColor: kBg,
        body: Stack(
          children: [
            const AmbientBackground(),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: IdentityHeader(
                      state: receiverState,
                      onOpenSettings: () => context.goSettings(),
                    ),
                  ),
                  const Spacer(),
                  HeroCode(
                    code: receiverState.code,
                    clipboardCode: receiverState.clipboardCode,
                  ),
                  const Spacer(),
                  IntegratedSendButton(
                    onPressed: () {
                      showSendSelectionSourceSheet(
                        context,
                        onChooseFiles: () => pickFiles(context, ref),
                        onChooseFolder: () => pickFolder(context, ref),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
```

- [ ] **Step 2: Remove the old FloatingActionButton from Scaffold**
Since we now use the `IntegratedSendButton` in the Column, the FAB should be removed.

### Task 6: Final Polish & Cleanup

**Files:**
- Delete: `flutter/lib/shell/widgets/mobile_idle_hub.dart`

- [x] **Step 1: Delete deprecated widget**
`mobile_idle_hub.dart` is no longer used.

- [x] **Step 2: Run flutter analyze and fix any issues**
Run: `flutter analyze`
Expected: No issues found.

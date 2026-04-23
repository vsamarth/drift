# Mobile-First Home Screen Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a mobile-first home screen featuring a centered "Unified Utility" card for receiving and a prominent Floating Action Button (FAB) for sending, while maintaining responsive support for desktop.

**Architecture:**
- Create a `MobileShell` widget for small screens and keep `DriftShell` (renamed to `DesktopShell`) for large screens.
- Implement `MobileIdleHub` to encapsulate the centered pairing card.
- Use a `ResponsiveLayout` helper to switch between shells based on screen width.

**Tech Stack:** Flutter, Riverpod

---

### Task 1: Create MobileIdleHub Component

**Files:**
- Create: `flutter/lib/shell/widgets/mobile_idle_hub.dart`

- [ ] **Step 1: Create the MobileIdleHub widget**
This widget will house the centered card containing the device info, settings, and the large pairing code.

```dart
class MobileIdleHub extends ConsumerStatefulWidget {
  const MobileIdleHub({super.key, required this.state, this.onOpenSettings});
  final ReceiverIdleViewState state;
  final VoidCallback? onOpenSettings;
  // ... (implement copy logic similar to ReceiveIdleCard)
}
```

- [ ] **Step 2: Style the Hero Code**
Make the code significantly larger than the desktop version (e.g., `fontSize: 32`) and center it within the card.

### Task 2: Implement Responsive Shell Switcher

**Files:**
- Create: `flutter/lib/shell/mobile_shell.dart`
- Modify: `flutter/lib/shell/drift_shell.dart` (Rename to DesktopShell)
- Modify: `flutter/lib/app/app_router.dart`

- [ ] **Step 1: Create MobileShell**
Implement the scaffold with the `MobileIdleHub` in the center and a `FloatingActionButton` at the bottom.

- [ ] **Step 2: Rename and Refactor DriftShell**
Rename `DriftShell` to `DesktopShell` and extract shared logic (like file picking) into a helper or mixin if necessary.

- [ ] **Step 3: Update Router**
Update the home route to use a new `ResponsiveShell` that switches between `MobileShell` and `DesktopShell` based on `MediaQuery.of(context).size.width`.

### Task 3: Visual Polish & Transitions

**Files:**
- Modify: `flutter/lib/theme/drift_theme.dart`

- [x] **Step 1: Refine Card Styling**
Ensure the mobile card has appropriate elevation, corner radius (24px), and internal padding to feel premium.

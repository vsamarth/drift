# Mobile-First Redesign (Clean Implementation)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a responsive shell that preserves the original desktop design while introducing a redesigned, card-based mobile flow.

**Architecture:** 
- `ResponsiveShell` as the top-level home widget.
- `DesktopShell` = Original `DriftShell` from `main`.
- `MobileShell` = New card-based layout from `feature/mobile-redesign`.

**Tech Stack:** Flutter, Riverpod.

---

### Task 1: Branch Setup & Context Preservation

- [ ] **Step 1: Save current redesign files to a temporary location**
We need `mobile_identity_card.dart` and `select_files_card.dart` and the logic for `MobileShell` from the current branch.

- [ ] **Step 2: Checkout main and create a new branch**
Run: `git checkout main && git checkout -b feature/mobile-flow-redesign`

### Task 2: Restore Original Desktop Design as DesktopShell

**Files:**
- Create: `flutter/lib/shell/desktop_shell.dart` (using content of `main:flutter/lib/shell/drift_shell.dart`, renamed to `DesktopShell`)

- [ ] **Step 1: Create DesktopShell.dart**
Copy `DriftShell` from `main` and rename the class to `DesktopShell`.

### Task 3: Port Mobile Redesign Components

**Files:**
- Create: `flutter/lib/shell/widgets/mobile_identity_card.dart`
- Create: `flutter/lib/shell/widgets/select_files_card.dart`
- Create: `flutter/lib/shell/widgets/shell_picking_actions.dart`

- [ ] **Step 1: Restore the redesign widgets**
Bring back the `MobileIdentityCard` (column-based) and `SelectFilesCard` from the `feature/mobile-redesign` branch.

### Task 4: Implement MobileShell

**Files:**
- Create: `flutter/lib/shell/mobile_shell.dart`

- [ ] **Step 1: Implement MobileShell with CustomScrollView**
Use the card-based layout structure.

### Task 5: Implement ResponsiveShell & Update Router

**Files:**
- Create: `flutter/lib/shell/responsive_shell.dart`
- Modify: `flutter/lib/app/app_router.dart`
- Delete: `flutter/lib/shell/drift_shell.dart`

- [ ] **Step 1: Create ResponsiveShell**
Logic to switch at 600px width.

- [ ] **Step 2: Update Router to use ResponsiveShell**
Replace `DriftShell` with `ResponsiveShell`.

- [ ] **Step 3: Delete the old drift_shell.dart**

### Task 6: Apply Settings Padding Fix

**Files:**
- Modify: `flutter/lib/features/settings/presentation/widgets/settings_page_body.dart`

- [ ] **Step 1: Add SafeArea and top padding**
As previously requested and implemented.

### Task 7: Verification

- [ ] **Step 1: Run analyze and tests**
Run: `cd flutter && flutter analyze && flutter test`
Expected: PASS

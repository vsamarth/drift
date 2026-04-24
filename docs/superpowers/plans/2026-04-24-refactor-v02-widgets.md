# Refactor V02 Widgets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove 'v02_' prefix from widget filenames and class names for a cleaner codebase.

**Architecture:** Rename files and classes to more descriptive names (`MobileIdentityCard` and `SelectFilesCard`).

**Tech Stack:** Flutter/Dart

---

### Task 1: Refactor Identity Card

**Files:**
- Rename: `flutter/lib/shell/widgets/v02_identity_card.dart` -> `flutter/lib/shell/widgets/mobile_identity_card.dart`
- Modify: `flutter/lib/shell/widgets/mobile_identity_card.dart`

- [ ] **Step 1: Rename the file**
Run: `mv flutter/lib/shell/widgets/v02_identity_card.dart flutter/lib/shell/widgets/mobile_identity_card.dart`

- [ ] **Step 2: Rename classes in mobile_identity_card.dart**
Change `V02IdentityCard` to `MobileIdentityCard` and `_V02IdentityCardState` to `_MobileIdentityCardState`.

### Task 2: Refactor Select Files Card

**Files:**
- Rename: `flutter/lib/shell/widgets/v02_select_files_card.dart` -> `flutter/lib/shell/widgets/select_files_card.dart`
- Modify: `flutter/lib/shell/widgets/select_files_card.dart`

- [ ] **Step 1: Rename the file**
Run: `mv flutter/lib/shell/widgets/v02_select_files_card.dart flutter/lib/shell/widgets/select_files_card.dart`

- [ ] **Step 2: Rename class in select_files_card.dart**
Change `V02SelectFilesCard` to `SelectFilesCard`.

### Task 3: Update Mobile Shell Usage

**Files:**
- Modify: `flutter/lib/shell/mobile_shell.dart`

- [ ] **Step 1: Update imports and usage**
Update imports to use `mobile_identity_card.dart` and `select_files_card.dart`.
Update class usage to `MobileIdentityCard` and `SelectFilesCard`.

### Task 4: Verification and Commit

- [ ] **Step 1: Run flutter analyze**
Run: `flutter analyze` in `flutter/` directory.

- [ ] **Step 2: Commit changes**
Commit with message: `refactor: rename v02 widgets to mobile names`

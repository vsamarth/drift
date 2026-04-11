# App Settings Full-Screen Design

**Goal:** Add a new full-screen settings experience in `app` that lets users edit device name, download folder, nearby discoverability, and discovery server from one shared form.

**Architecture:** Build one settings feature slice with a shared controller, repository, and state model. The page should be full-screen on both desktop and mobile, with a back affordance and a save footer. The receive idle gear button will open this page, and the page will own dirty-state tracking, validation, save confirmation, and unsaved-change warnings.

**Tech Stack:** Flutter, Riverpod, `shared_preferences`, and the existing app theming.

---

## Current State

- The `app` codebase does not yet have a dedicated settings feature.
- The receive idle card already exposes a settings button entry point.
- The app shell is still shared across platforms, so the first settings version should not split into separate desktop and mobile feature trees.
- The Flutter reference app already demonstrates the intended visual language: calm white surface, cyan primary actions, compact sectioning, and minimal chrome.

## Proposed Design

### 1. Settings Feature Structure

Add a new `app/lib/features/settings/` feature slice containing:

- `application/state.dart`
- `application/controller.dart`
- `application/repository.dart`
- `presentation/view.dart`
- `presentation/widgets/settings_page.dart`

The feature owns:

- the editable settings values
- save state
- error state
- dirty-state detection
- navigation confirmation when leaving with unsaved edits

The rest of the app should only talk to the feature through its public view/controller APIs.

### 2. Settings Data Model

The first version includes four fields:

- Device name
- Save received files to
- Nearby discoverability
- Discovery server

The app should keep these values in one persisted settings record. That record becomes the source of truth for:

- the device label shown in the receive idle screen
- the download directory used for received files
- whether the device advertises itself to nearby receivers
- the custom discovery server URL, if present

Empty discovery server input should mean “use the default server”.

If no persisted settings record exists yet, the repository should create one with defaults on first load:

- device name from the exported Rust `randomDeviceName()` API
- default download folder from the app’s existing platform-specific default (`${Directory.systemTemp.path}/Drift` in the current receiver source)
- discoverability enabled by default
- discovery server empty, meaning use the built-in default

The generated device name should be stored immediately so later launches use the same value unless the user changes it.

### 3. Screen Layout

The settings page should be full-screen for both desktop and mobile.

Layout requirements:

- top bar with a back button and `Settings` title
- single scrollable form body
- sticky footer with save action and helper copy
- error banner near the top when save fails

Form section order:

1. Device name
2. Save received files to
3. Nearby discoverability
4. Advanced section divider
5. Discovery server

Visual direction:

- reuse the app theme tokens from `app/lib/theme/drift_theme.dart`
- keep the same restrained, bordered, lightweight style used elsewhere in `app`
- use the cyan primary button treatment for save
- keep the page simple rather than decorative

### 4. Navigation

The receive idle settings button should push the new full-screen settings page.

Back navigation behavior:

- if there are no unsaved changes, return immediately
- if there are unsaved changes, show a confirmation dialog before leaving
- the dialog should offer discard and stay/edit choices

The page should stay on-screen after a successful save.

### 5. Persistence and Validation

The repository layer should handle reading and saving the `SharedPreferences`-backed settings record.

Validation rules for v1:

- device name must not be empty after trimming
- save folder must not be empty after trimming
- discovery server may be empty, but if provided it should be trimmed
- discoverability is a boolean toggle and does not need extra validation

Save behavior:

- if the form values match the persisted record, do nothing
- if persistence fails, keep the user’s edits visible and show an error banner
- if save succeeds, update the baseline values so the form is no longer dirty

### 6. Error Handling

The settings page should surface errors in-place instead of navigating away.

Expected failure modes:

- storage write failure
- invalid or rejected folder selection
- invalid field values

The page should not clear user edits on failure.

### 7. Testing Plan

Add tests for:

- controller save success
- controller save failure
- settings page renders the expected fields and sections
- save button enables only when the form is dirty
- unsaved-change warning appears when navigating back with edits
- receive idle settings button opens the settings page

Keep tests focused on behavior, not implementation details.

## Scope Notes

- This design intentionally keeps the settings experience as one full-screen page for both desktop and mobile.
- It does not add a separate desktop panel variant.
- It does not expand the settings surface beyond the four requested fields.
- If future work needs more settings, the shared controller/repository structure should support that without changing navigation.

# Send Transfer Route Design

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the send flow go directly from draft to a live transfer page that starts the FRB transfer immediately and shows progress, without a separate review screen.

**Architecture:** Keep `SendController` as the single owner of send-flow state, but let it build a fully validated `SendRequestData` snapshot before navigation. The draft page remains the editing surface for files and destination selection. A new transfer route receives the built request, starts the FRB transfer on entry, and renders the live transfer lifecycle and final result in one place.

**Tech Stack:** Flutter, Riverpod, GoRouter, Flutter Rust Bridge, `flutter_test`

---

## Scope

This design replaces the review step with a direct transfer screen. It keeps the current destination model and nearby selection behavior, but removes the extra intermediate page between `Send` and the FRB transfer.

The transfer page is responsible for:
- showing the request details that will be used
- starting the FRB transfer immediately
- rendering progress and outcome state
- handling back navigation and cancellation cleanly

---

## State Model

### Send flow phase

Keep the send flow phases small:
- `idle`
- `drafting`
- `transferring`
- `result`

There is no `reviewing` phase.

### Destination model

Keep destination as a tagged state with three explicit modes:
- `none`
- `code`
- `nearby`

This avoids pre-filling the code field when a nearby receiver is selected, while still allowing either send path to build a valid request.

### Transfer request snapshot

Add a `SendRequestData` snapshot object in Dart that mirrors the FRB request shape:
- `destinationMode`
- `paths`
- `deviceName`
- `deviceType`
- `code`
- `ticket`
- `lanDestinationLabel`
- `serverUrl`

This object becomes the handoff between the draft page and the transfer page. The transfer page renders it read-only and uses it to start FRB.

---

## UI Flow

### Draft page

The draft page continues to do the following:
- show selected files
- let the user add or remove files
- scan nearby receivers locally
- let the user choose either a code or a nearby receiver

When the user taps `Send`:
- the controller validates that a request can be built
- the app navigates directly to the transfer route
- the transfer route starts the FRB transfer immediately

No confirmation screen appears.

### Transfer page

The new transfer page shows:
- destination summary
- selected files
- local device name and type
- the live FRB progress state
- the final result when transfer ends

It should feel like the actual “sending” screen, not an intermediate confirmation page.

### Back behavior

Back navigation from the transfer page should cancel the in-flight transfer if one exists, then return the app to the drafting state with the current selection preserved.

If the transfer has already completed, back should exit the transfer result and return to the draft flow or the appropriate previous screen based on current app navigation.

---

## Data Flow

1. User selects files and a destination in the draft page.
2. `SendController` stores the destination as either `code` or `nearby`.
3. The draft page asks the controller for a validated `SendRequestData`.
4. If valid, navigation pushes the transfer route with that request.
5. The transfer route starts `startSendTransfer(...)` immediately.
6. FRB emits `SendTransferEvent` updates.
7. Dart maps those updates into controller state and transfer UI state.
8. When the stream completes or fails, the page displays the final result.

Nearby selection never pre-fills the code field. It only changes destination mode to `nearby` and carries the ticket through to the request snapshot.

---

## Components

### `SendController`

Responsibilities:
- own draft files and destination mode
- validate whether a request can be built
- build `SendRequestData`
- optionally retain the active transfer request/result state

Not responsibilities:
- route building
- FRB stream subscription
- rendering transfer progress

### `SendTransferRoute`

Responsibilities:
- receive the built request
- start transfer on entry
- render request summary and live status
- cancel transfer on back when needed

Not responsibilities:
- editing files or destination
- deciding whether the request is valid

### FRB adapter

Keep the existing thin adapter around the generated FRB API:
- `startSendTransfer(...)`
- `cancelActiveSendTransfer()`

The adapter should remain the boundary between Dart state and Rust transfer updates.

---

## Error Handling

- If the controller cannot build a valid request, `Send` stays disabled.
- If transfer start fails immediately, the transfer page should show a failed state instead of crashing.
- FRB `failed`, `cancelled`, and `declined` events should map into user-visible terminal states.
- Nearby selection should never populate the code field, so code validation and nearby selection stay distinct.

---

## Testing

Add or update tests for:

- destination mode state
  - typing a code stores `code`
  - selecting nearby stores `nearby`
  - nearby selection does not fill the code field

- request building
  - code destination builds a request with code/server URL
  - nearby destination builds a request with ticket/label

- draft button behavior
  - Send stays disabled until a valid destination exists
  - tapping Send navigates directly to the transfer route

- transfer page
  - route renders request details
  - transfer starts on route entry
  - back cancels an active transfer and returns to drafting

- regressions
  - shell and router behavior still work
  - send feature placeholder still reflects the current phase

---

## Non-Goals

- No separate review page
- No shell-wide send session orchestration
- No retry/send-again flow yet
- No “choose another device” post-result action yet
- No prefilled code from nearby selection


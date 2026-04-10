# Receiver Feature Vision

Status: Draft
Date: 2026-04-11

## Why This Exists

The current `app/` shell is intentionally minimal: it shows two placeholder sections, one for Receiver and one for Send, inside a fixed utility-sized desktop window. That is the right foundation for now because it keeps the app easy to understand while we gradually rebuild the product in a more maintainable direction.

This document defines the intended shape of the Receive surface so we can complete it without recreating the old app's coupling. The goal is not to reproduce every historical behavior at once. The goal is to establish a clean, feature-owned architecture that can grow into the real receiver flow later, including the eventual Rust-backed runtime.

## Vision

The receive surface should be split into two clean responsibilities:

- `Receiver` owns availability, pairing, and discoverability.
- `Transfers` owns offers, transfer sessions, progress, and accept/decline/cancel actions.

Together they form the receive screen, but they should not share one overloaded state machine.

### Receiver Lifecycle

The receiver service should stay small and honest. Its lifecycle states are:

- `starting`
- `ready`
- `stopped`
- `failed`

These states answer one question only: is the receiver alive and ready to accept work?

### Transfers Session

Transfers should be modeled separately as a session state machine:

- `idle`
- `offerPending`
- `receiving`
- `completed`
- `failed`

These states answer a different question: what transfer, if any, is happening right now?

The receive UI should compose those two layers. For example:

- `starting` + `idle` shows the receiver badge as `Registering` and the lower panel as `No offers yet`
- `ready` + `idle` shows the receiver badge as `Ready` and the lower panel as `No offers yet`
- `ready` + `offerPending` shows the receiver badge as `Ready` and the lower panel as an incoming offer card
- `ready` + `receiving` keeps the badge as `Ready` while the lower panel shows progress
- `stopped` or `failed` moves the badge to `Unavailable`

The key rule is that an incoming offer does **not** change receiver lifecycle to `stopped`. The receiver stays `ready` while a transfer is pending or active.

The feature should feel calm, predictable, and utility-like. It should not depend on shell-level navigation tricks or shared global app state beyond what is necessary to render and coordinate the receive flow.

## Non-Goals

- No Rust integration in this first pass of the new app architecture.
- No send flow implementation work beyond the send placeholder already in place.
- No generic app-wide state manager that mixes send and receive concerns together.
- No attempt to preserve the old Flutter implementation structure file-for-file.
- No settings or preferences redesign as part of Receiver itself.

## Design Principles

### 1. Feature Ownership

Receiver and Transfers should each own their own:

- visual tree
- state model
- controller or notifier
- feature-specific view models
- tests

The shell should only compose the receive surface from those features. It should not know the details of the receiver or transfer states.

### 2. Clear State Boundaries

Receiver should expose a small, explicit availability state surface. Transfers should expose a separate session state surface. The UI should consume those feature state objects rather than reaching into app-wide internals.

### 3. Minimal Shared Surface

Only truly shared concepts should live outside the feature:

- theme primitives
- a few reusable layout atoms
- shared formatting helpers if needed

Anything specific to Receiver or Transfers should stay in their own feature folders.

### 4. Testable Pieces

Every meaningful unit should be easy to test independently:

- the receiver lifecycle model
- the transfers session model
- the state-to-UI mapping
- the feature's placeholder and eventual real states
- any transition logic that decides what the receive surface should show

## Proposed Architecture

### Folder Structure

The receive surface should grow into two feature modules:

```text
app/lib/features/receiver/
  application/
    controller.dart
    state.dart
  presentation/
    badge.dart
    widgets/
      status_chip.dart

app/lib/features/transfers/
  application/
    controller.dart
    state.dart
  presentation/
    view.dart
    widgets/
      idle_card.dart
      offer_card.dart
      receiving_card.dart
      completed_card.dart
      error_card.dart
```

Not every file needs to exist immediately, but this is the direction the feature should grow toward.

### Public API

Each feature should export a small public surface only:

- `ReceiverFeature` and `TransfersFeature` entrypoints
- feature-local provider sets that include the controller and view state
- the smallest possible set of widgets required by the shell

Internal widgets should remain private or be kept inside the feature folder.

### State Model

Receiver should be modeled as a feature-owned state machine with explicit lifecycle variants:

- `ReceiveStarting`
- `ReceiveReady`
- `ReceiveStopped`
- `ReceiveFailed`

Transfers should be modeled separately with explicit session variants:

- `TransferIdle`
- `TransferOfferPending`
- `TransferReceiving`
- `TransferCompleted`
- `TransferFailed`

Each state should carry only what the relevant view needs. The UI should not need to reach into unrelated data structures to know what to render.

The state machines should make transitions explicit. For example:

- `starting` -> `ready` when startup completes
- `ready` -> `offerPending` when an incoming offer arrives
- `offerPending` -> `receiving` when the offer is accepted
- `receiving` -> `completed` when the transfer finishes
- any active transfer state -> `failed` when the transfer or setup fails
- any active transfer state -> `idle` when the user cancels, declines, or the session closes cleanly
- `stopped` or `failed` -> `starting` when the receiver is reset or re-registered

Useful fields may include:

- device name
- device type
- receiver code / badge
- offer summary
- list of incoming items
- transfer progress
- speed and ETA
- completion result
- user-facing error text

### Controller Responsibility

The receiver controller should be the only place that handles receiver-specific user actions and state transitions, such as:

- registering the receiver at startup
- resetting or stopping the receiver cleanly

The transfers controller should be the only place that handles transfer-specific actions and transitions, such as:

- accepting an incoming offer
- declining an offer
- canceling an active transfer
- retrying after an error

Each controller should stay in its own lane. Neither should contain rendering logic.

### View Responsibility

The view layer should be split by state:

- unavailable view for setup or offline status
- registering view for startup or background initialization
- idle view for the receiver surface and code display
- review view for incoming offers
- receiving view for progress and cancel action
- stopped view for a clean terminal state or manual reset
- completed view for summary and follow-up action
- error view for recovery

Each view should be a pure function of the feature state as much as possible.

Receiver-specific views should handle the badge, code, and availability chrome.
Transfers-specific views should handle the lower card area that changes when offers or sessions appear.

## UX Direction

The new app shell is intentionally small and utility-like, so the receive surface should lean into that.

### Idle Receiver Surface

This is the default top-half placeholder today, and it should evolve into the permanent idle receiver surface.

Goals:

- show the receiver identity clearly
- show the pairing or receiver code prominently
- communicate readiness without visual noise
- leave room for a future "open settings" or "copy code" action

### Offer Review

When a sender connects, Transfers should switch to a review state that explains:

- who is sending
- how many items are coming
- what the rough size is
- where files will be saved

This screen should be deliberately conservative and trust-oriented. It should make declining as easy as accepting.

In the split architecture, this belongs to `Transfers`, not `Receiver`.

### Receiving

When the transfer starts, the UI should shift into a progress-focused state:

- transfer progress
- speed
- ETA if known
- incoming file list
- cancel action

This state should feel calm rather than dramatic. The emphasis is clarity and confidence.

In the split architecture, this also belongs to `Transfers`, not `Receiver`.

### Completion

After a successful transfer, Transfers should present a brief summary with enough detail to confirm what arrived and where it went.

### Errors

Errors should be actionable and human-readable.

The feature should avoid dumping raw errors directly into the UI. Instead, map them into user-facing states that suggest the next step:

- retry
- cancel
- return to idle

## Data Flow

The intended data flow is:

1. The shell renders the receive surface.
2. The receiver controller owns availability and pairing state.
3. The transfers controller owns active session state.
4. The UI composes the receiver badge/code area with the transfer card area.
5. User actions flow back through the relevant controller.

This keeps the shell thin and the feature independently testable.

## Riverpod Shape

The new app already uses Riverpod, so Receiver and Transfers should use generated providers consistently.

Suggested pattern:

- one `@riverpod` controller or repository provider for receiver availability
- one `@riverpod` controller or repository provider for transfer sessions
- one generated provider for each feature view state
- providers declared at top level inside the feature files, not in the shell

Best practice here is to keep provider names feature-local and avoid making the shell aware of implementation details.

## UI Composition Strategy

The receive surface should be built from a small set of reusable cards:

- receiver header / identity block
- code block
- offer review card
- receiving progress card
- completion summary card
- error card

Each card should be focused enough to test in isolation.

The shell should never need to know how those cards work internally. It should simply show the composed feature widgets.

## Testing Strategy

Receiver and Transfers should be tested at three levels:

### 1. Widget Tests

Cover the visible states:

- receiver idle / unavailable / registering badge states
- transfer idle / offer pending / receiving / completed / error cards

The tests should verify the right card appears and that the key text and actions are present.

### 2. State Transition Tests

Test the controller logic separately:

- receiver registration lifecycle transitions
- offer accepted from review
- offer declined from review
- transfer canceled from receiving
- error recovery path

These tests should not require a full widget tree unless the transition logic is tightly coupled to the view.

### 3. Accessibility / Layout Sanity

Because the app is intentionally fixed to a utility-sized window, Receiver should be tested for:

- no overflow at the target window size
- text still fits at normal desktop scaling
- primary actions remain reachable

## Clean Architecture Expectations

The main risk in rebuilding this surface is over-centralizing too early.

The receive surface should avoid these patterns:

- a giant monolithic view file
- shell widgets importing feature internals
- app-level state objects that mix send and receive concerns
- controllers that become half view-model, half service, half formatter
- one controller trying to own both lifecycle and transfer session state

The receive surface should prefer:

- small files
- explicit state objects
- private helper widgets
- clear provider boundaries

## Suggested Implementation Phases

### Phase 1: Feature Skeleton

Create the feature modules with:

- `ReceiverFeature`
- `TransfersFeature`
- simple state models
- placeholder cards for receiver badge and transfer states
- widget tests

This gets the architecture in place quickly without requiring the full runtime.

### Phase 2: UI State Expansion

Add the receiving, completed, and error views for transfers.

At this stage the feature should already look and behave like a real product surface, even if the data is still mocked.

### Phase 3: Controller Discipline

Add the actual state transition logic in feature-owned controllers or notifiers.

This should remain UI-first and still not depend on Rust.

### Phase 4: Runtime Integration

Once the app architecture is stable, connect Receiver to the Rust-backed runtime in `crates/app/src/receiver` and connect Transfers to the Rust-backed transfer stream.

That integration should happen behind the feature's public API so the UI does not need to be rewritten.

## Open Assumptions

This draft assumes:

- the new `app/` is the primary UI we are rebuilding
- Receiver should remain desktop-first for the moment
- the current shell can stay utility-sized while we refine the feature
- Rust integration will come later, behind feature boundaries

## Success Criteria

This receive-surface design is successful if:

- the feature can be understood without reading the whole app
- the shell stays minimal
- the receiver and transfers layers can be tested independently
- adding the real runtime later does not force a rewrite of the UI
- the code remains easy to split further when the Rust layer is ready

## Summary

The receive surface should become a calm, desktop-first composition of two small feature modules: Receiver for availability and Transfers for session state. The app shell should stay thin, and the eventual Rust integration should be layered underneath the feature boundaries rather than woven through the UI.

# Send Transfer States Design

## Goal

Match the visible send-transfer progression from `ref-app` in the current Flutter app while keeping the implementation small, explicit, and easy to follow.

The transfer page should display the same state progression the reference app shows:

- `connecting`
- `waitingForDecision`
- `accepted`
- `sending`
- `completed`
- `declined`
- `cancelled`
- `failed`

The send flow should still be owned by one controller. We are not rebuilding the shell/session architecture from `ref-app`.

## Guiding Principles

- Keep one send controller as the lifecycle owner.
- Keep the transfer route as a pure view over controller state.
- Model visible transfer states explicitly instead of collapsing them into one generic "transferring" state.
- Prefer derived view data over widget-local state.
- Use small mappers and reducers where they reduce branching in UI code.

## State Model

The current send state is too coarse for the desired UI. We will expand it into three layers:

### 1. Draft State

This remains responsible for:

- selected files
- destination mode
- code destination or nearby destination ticket
- buildable request snapshot

The draft layer still decides whether a send request is valid.

### 2. Transfer State

Transfer state should track the exact visible phase reported by FRB:

- `connecting`
- `waitingForDecision`
- `accepted`
- `sending`
- `cancelling`

The transfer state should also carry the live data needed to render the page:

- destination label
- item count
- total size
- bytes sent
- total bytes
- progress plan
- progress snapshot
- remote device type
- optional speed and ETA labels

### 3. Result State

Result state should represent terminal outcomes:

- `completed`
- `declined`
- `cancelled`
- `failed`

Result state should also carry:

- the final summary shown to the user
- completion metrics when available
- the final plan/snapshot if available

## Controller Responsibilities

`SendController` remains the only feature controller.

It should:

- own the draft and transfer lifecycle
- validate and normalize destination input
- build the request snapshot used to start a transfer
- start the FRB transfer on the direct transfer route
- reduce FRB updates into explicit send states
- cancel the active transfer when asked
- clear the transfer subscription when the flow ends

The controller should not render UI-specific widgets, but it may expose view-ready state and labels.

## FRB Event Mapping

FRB updates already carry enough data to drive the transfer page. The app should map them as follows:

- `connecting` -> show the request has been sent
- `waitingForDecision` -> show the transfer is waiting for the receiver
- `accepted` -> show the receiver accepted
- `sending` -> show progress and throughput
- `completed` -> show a success result
- `declined` -> show a declined result
- `cancelled` -> show a cancelled result
- `failed` -> show a failed result

When FRB provides a plan or snapshot, the app should preserve it in state and use it to render per-file progress.

## Transfer Page Behavior

The transfer route should stay a single route. It should not navigate to a separate review screen.

On entry:

- the page immediately starts the transfer
- the request summary is shown right away
- the visible state changes as FRB events arrive

During transfer:

- summary stays visible
- file list stays visible
- the active state section changes based on the current phase
- progress details update live during `sending`

On terminal states:

- the page switches to a result card
- the result card matches the outcome
- the user can back out or dismiss as appropriate

## UI Sections

The page should be composed of small sections so each state is easy to render:

- request summary
- file progress list
- live state banner
- result card

The file list should reflect the current plan/snapshot when available.

If there is no plan yet, the list should still show the selected files in a stable order.

## Error Handling

The controller should turn transport failures and FRB errors into a terminal `failed` result.

The page should distinguish:

- peer declined
- cancelled
- network or internal failure

User-facing copy should remain short and direct.

## Testing

Add tests for:

- draft request construction for code and nearby destinations
- controller reduction of FRB updates into each transfer phase
- result mapping for completed, declined, cancelled, and failed outcomes
- transfer page rendering for:
  - connecting
  - waiting for decision
  - accepted
  - sending
  - completed
  - declined
  - cancelled
  - failed

Prefer tests that validate the phase and the key visible text, not implementation details.

## Scope Boundaries

In scope:

- explicit transfer phase modeling
- richer result rendering
- lightweight per-file progress rendering

Out of scope for this pass:

- shell-level session orchestration
- route review step
- retry/send-again flows
- nearby discovery redesign
- result analytics beyond what is needed to render the page


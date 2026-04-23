# Design Spec: Transfer Success Moment

## Overview
Implement a subtle, celebratory "Success Moment" animation when a transfer reaches 100%. This provides tactile feedback and a sense of accomplishment before transitioning to the final result summary.

## Goals
- Provide clear, rewarding visual feedback for a completed transfer.
- Ensure the transition from "Active" to "Result" feels smooth rather than jarring.
- Maintain the "simple and subtle" aesthetic of the Drift app.

## Proposed Changes

### 1. `RecipientAvatar` Animation Logic
The `RecipientAvatar` widget will be updated to handle the "Success Moment" sequence:
- **New AnimationController:** A `_successController` will be added to handle the pop and glow transitions.
- **Trigger:** When `progress` reaches 1.0, the `didUpdateWidget` method will trigger the success sequence.
- **Scale Animation:** The central avatar (circle and icon) will scale up to ~1.12x and back to 1.0 using `Curves.backOut` over 500ms.
- **Color Transition:** The progress ring will transition from `kAccentCyan` to Success Green (`0xFF49B36C`).
- **Final Pulse:** A one-time celebratory ripple animation that is larger and more distinct than the standard "waiting" ripples.

### 2. Controller State Delays
To allow the animation to play out before the UI switches layouts, we will introduce a brief "breathing room" delay:
- **`TransfersServiceController` (Receiver):** In the `receiving` state handling, when the `completed` event is received, add a `Future.delayed(const Duration(milliseconds: 1000))` before updating the state to `completed`.
- **`SendController` (Sender):** Similar delay logic when the transfer snapshot indicates 100% completion or the result state is reached.

### 3. UI Refinement
- During the 1-second success window, the "Cancel" button in the footer should be hidden or disabled to indicate the transfer is already finalized.

## Implementation Details

### `RecipientAvatar` changes:
- Add `_successController` and `_scaleAnimation`.
- Update `CircularProgressIndicator` color based on success state.
- Update `Stack` to include a success-specific ripple.

### `TransfersServiceController` changes:
- Modify `_subscription` listener for `ReceiverTransferPhase.completed`.
- Add a local boolean or state to track "waiting for animation" if needed, or simply delay the state transition.

## Testing Strategy
- **Manual Verification:** Perform a transfer and verify the "pop" animation plays smoothly when reaching 100%.
- **Edge Case:** Verify that cancelling *at* the 100% mark (if possible) doesn't cause a crash.
- **Regression:** Ensure the standard waiting ripples still work as expected for new transfers.

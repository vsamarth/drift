# Design Spec: Mobile-First Ambient Dashboard

## Goal
Replace the "boxy" and "card-like" home page with a cleaner, more integrated "Ambient Canvas" vision. The redesign focuses on using the entire screen as a status dashboard, moving away from constrained widgets to a layered, motion-driven interface.

## Visual Language: "The Ambient Canvas"
- **Integration:** Remove all explicit cards, borders, and heavy shadows from the idle state.
- **Background as Interface:** The screen background provides the "status" (alive/listening) through motion and color, rather than just being a container.
- **Typography as Hero:** Information (the receive code) is the primary visual element, rendered with scale and whitespace instead of boxes.

## Core Components

### 1. AmbientBackground
- **Visual:** A soft, large-scale radial gradient.
- **Animation:** A "breathing" effect (4-6 second loop) where the gradient scale and opacity subtly shift.
- **Colors:** Utilizes `kAccentCyan` and `kAccentWarm` at very low opacities (5-10%).

### 2. IdentityHeader
- **Layout:** Positioned at the top of the safe area.
- **Device Name:** `driftSans` (14pt, SemiBold, `kInk`).
- **Status Label:** A small status dot (with a soft glow) and "Online" or "Listening" text on the right.

### 3. HeroCode
- **Typography:** `driftMono` (64pt+, ExtraBold, `kInk`).
- **Layout:** Centered on the screen with a wide gap (letter-spacing or padding) between the two 3-digit halves.
- **Interaction:** The entire center region is a hit target for copying. 
- **Feedback:** On tap:
    - `HapticFeedback.mediumImpact()`
    - A brief "Copied" label replaces the "Tap to copy" hint.
    - A subtle ripple effect on the `AmbientBackground`.

### 4. IntegratedSendButton
- **Layout:** Bottom-anchored, wide pill-shaped button.
- **Style:** Solid `kInk` background, `kSurface` text/icon.
- **Padding:** 24pt horizontal margin from screen edges.

## Technical Implementation

### Layering (Stack)
1. **Background Layer:** `AmbientBackground` (The animated gradient).
2. **UI Layer:** A `Column` containing the `IdentityHeader`, a `Spacer`, the `HeroCode`, another `Spacer`, and the `IntegratedSendButton`.

### State Management
- Continue using `receiverIdleViewStateProvider` for device name, status, and code.
- Add a local `AnimationController` for the background heartbeat.
- Local `useState` or `StatefulWidget` logic for the "Copied" success moment.

## User Review
Please review the spec above. I will wait for your approval before proceeding to the implementation plan.

# Design Spec: Mobile-First Home Screen Redesign

## Overview
Redesign the home screen to feel native to mobile devices while preserving the minimalist utility aesthetic of the desktop app. The new layout will center on a "Unified Utility" card with a prominent pairing code and a bottom-aligned Floating Action Button (FAB) for sending files.

## Goals
- Create a "mobile-first" experience with touch-friendly targets.
- Preserve minimalist utility branding.
- Re-use existing business logic and components where possible.
- Focus attention on the most common mobile action: sharing/receiving via code.

## Proposed Changes

### 1. Unified Utility Card
- A single, centered card (or slightly top-weighted) that contains:
    - **Header:** Device name and discoverability status (online/offline dot).
    - **Settings:** A subtle gear icon in the top-right of the card.
    - **Center (Hero):** The pairing code, displayed in a large, monospace font. Tap-to-copy interaction with the "Copied" feedback we already implemented.
- The card will have a subtle shadow and rounded corners (16-24px) to make it feel like a physical object.

### 2. Primary Action (FAB)
- A large, circular or pill-shaped Floating Action Button (FAB) at the bottom center of the screen.
- Icon: `Icons.add_rounded` or `Icons.file_upload_outlined`.
- Action: Opens the file/folder picker (replacing the desktop "Drop Zone").

### 3. Responsive Layout Logic
- We will implement a `MobileShell` and a `DesktopShell` (or use a `ResponsiveLayout` helper).
- **Mobile View:** Uses the new centered card + FAB.
- **Desktop View:** Preserves the current stacked layout for wide screens.

## Technical Details
- **New Widget:** `MobileIdleHub` which will encapsulate the centered card logic.
- **Controller Refactor:** Extract any logic tied to the current `DriftShell` into a shared `AppShellController` if needed, though most is already in Riverpod providers.
- **Theme:** Use `kSurface` for the card and a slightly darker `kBg` for the screen background to create depth.

## Testing Strategy
- **Manual Verification:** Test on small and large mobile screen sizes (simulator/emulator).
- **Regression:** Ensure the desktop layout is unchanged on wide screens.
- **Interaction:** Verify tap-to-copy and FAB triggers work smoothly.

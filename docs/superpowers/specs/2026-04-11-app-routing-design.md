# App Routing Design

## Goal

Replace ad hoc `Navigator.push` calls in `app/` with a small router setup so the current screens are easier to navigate and future screens can be added without scattering route logic.

## Scope

This change covers only the `app` package routing layer and the small set of screens currently reachable from the home shell.

In scope:

- Home screen route
- Settings route
- Send draft preview route
- Back navigation behavior
- Route-based navigation from the home shell

Out of scope:

- Changing the visual design of existing screens
- Adding new transfer workflow steps
- Deep linking from outside the app beyond route definitions
- Changes to the Rust bridge or transfer logic

## Proposed Architecture

Use `go_router` as the top-level router for `MaterialApp.router`.

Route map:

- `/` -> home shell
- `/settings` -> settings page
- `/send/draft` -> `SendDraftPreview`

The home route remains the landing page and continues to show the receiver card plus the drop zone vertically stacked.

## Navigation Behavior

- Tapping the settings button navigates to `/settings`.
- Dropping files or choosing files on the home screen navigates to `/send/draft`.
- The draft preview page includes a visible back button in the app bar that pops the route.
- Route transitions should preserve the current screen content and styling.

## Implementation Notes

- Keep route construction centralized in one router file.
- Prefer named route helpers over string literals scattered through the UI.
- Keep the page widgets themselves unaware of router configuration where possible.
- Preserve the existing home-shell composition; only the navigation mechanism changes.

## Testing

Add or update tests to cover:

- Home shell still renders the receiver card and drop zone
- Settings navigation opens the settings page
- Draft preview opens from the home screen
- Back button on the draft preview returns to home

## Success Criteria

- The app builds with the new router setup.
- Existing screens look unchanged.
- Navigation is driven by router routes rather than direct `Navigator.push` calls in the home shell.
- The draft preview page can be revisited via a stable route path.

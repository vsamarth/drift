# Send Draft Additions Design

## Goal

Let the send draft preview screen support adding more files and folders in place, with two separate right-aligned actions below the preview card, similar to the Flutter reference.

## Scope

This change is limited to the Flutter `app/` send preview flow.

In scope:

- Add `Add files` and `Add folders` actions below the preview card
- Keep the actions right-aligned under the preview area
- Reuse the existing send selection picker provider
- Append picked files and folders into the current draft without leaving the preview screen
- Preserve the existing route-based entry into `SendDraftPreview`
- Keep directory rendering behavior from the folder-support work

Out of scope:

- Changing the send selection chooser sheet
- Changing router structure
- Adding send-backend transfer behavior beyond staging the draft list
- Restructuring the entire send page into the full Flutter mobile send-draft layout

## Proposed Architecture

Keep `SendDraftPreview` as the draft staging screen, but make it own a small mutable selection list for the current route session.

Recommended structure:

- `SendDraftPreview` receives the initial list from the route extra
- The preview card renders the current list
- Two action buttons below the card call the existing picker provider:
  - `Add files`
  - `Add folders`
- When a selection comes back, append the new items to the current list and rebuild the preview in place

This keeps the screen behavior simple:

- preview stays visible
- additions update the same screen
- no extra navigation is needed after the initial route open

## UX

The layout should follow the reference pattern:

- Keep the preview card at the top of the page content
- Place the add actions below it
- Align both buttons to the right
- Keep the two actions separate, not combined into a menu

Button labels:

- `Add files`
- `Add folders`

The actions should feel like incremental editing of the current draft, not a second chooser screen.

## Data Flow

1. The app routes to `SendDraftPreview` with the initial selected items.
2. The screen renders the current preview card.
3. User taps `Add files` or `Add folders`.
4. The corresponding picker method returns new items.
5. The screen appends the new items to the current list.
6. The preview list updates in place.

If the picker returns nothing, the current preview remains unchanged.

## Implementation Notes

- Keep directory rows rendered as folders with an empty size field.
- Keep file rows unchanged.
- Preserve the current back navigation behavior.
- Use the same picker provider introduced by the folder-support work.
- Keep the current route entry point and `extra`-based initial selection intact.

## Testing

Add or update tests to cover:

- The preview page still opens with the initial selection
- Tapping `Add files` appends file items to the current preview
- Tapping `Add folders` appends folder items to the current preview
- The preview remains on the same screen after adding items
- Directory rows still render with folder icons and empty size cells after additions

## Success Criteria

- The send draft preview has two separate right-aligned add actions below the preview card.
- Files and folders can be added without leaving the page.
- The page updates in place and continues to show files and folders distinctly.
- The screen feels close to the Flutter reference without copying unrelated mobile sections.

# Send Folder Support Design

## Goal

Allow the send flow to accept directories as first-class items without changing the main entry point. The `Select Files` button should remain the same, but it should also let the user choose a folder through a small chooser sheet. Dropped folders should also appear in the preview page.

## Scope

This change is limited to the Flutter `app/` package send flow.

In scope:

- Keep the `Select Files` button label unchanged
- Add a small chooser sheet with `Files` and `Folder`
- Support picking a directory from the chooser
- Continue supporting file picking
- Continue supporting drag-and-drop of folders
- Render directories in the send preview with a folder icon
- Show an empty size field for directories

Out of scope:

- Any send-backend behavior beyond previewing the selection
- Changes to the transfer protocol
- Combining files and folders in the same native picker dialog
- Changing the preview page layout beyond the directory row treatment

## Proposed Architecture

Keep the current home shell and preview route structure.

Add a small selection chooser component that sits behind `Select Files`:

- `Files` -> existing file picker flow
- `Folder` -> directory picker flow

The picker result should be normalized into one preview item type that can represent either a file or a directory.

Recommended shape:

- `path`
- `name`
- `kind` with values `file` or `directory`
- `sizeBytes` nullable

The drag-and-drop path should be classified the same way:

- file paths become file items
- directory paths become directory items

## UX

The chooser should be lightweight and visually secondary to the main send panel:

- Tap `Select Files`
- Open a compact sheet or popover
- Offer two clear actions:
  - `Files`
  - `Folder`

This keeps the primary screen simple while still making the folder capability discoverable.

Preview rendering rules:

- Files keep the current file row appearance
- Directories use a folder icon
- Directory rows show an empty size column
- The preview summary should continue to count all selected items

## Data Flow

1. User taps `Select Files`.
2. The chooser sheet opens.
3. User selects either files or a folder.
4. The selected path(s) are normalized into preview items.
5. The app navigates to `SendDraftPreview`.
6. `SendDraftPreview` renders files and folders in the same list.

Dropped paths follow the same normalization step before navigation.

## Implementation Notes

- Keep the `Select Files` label unchanged.
- Prefer a single preview item model rather than separate file-only and directory-only preview screens.
- Keep the folder support local to the send flow so it does not affect receive logic.
- Preserve the current route structure and back navigation behavior.

## Testing

Add or update tests to cover:

- `Select Files` still opens the chooser entry point
- Choosing `Files` still opens the file picker flow
- Choosing `Folder` opens the directory picker flow
- Dropped folders are accepted and routed to preview
- Directory rows render with a folder icon
- Directory rows show an empty size field
- File rows continue to show size values

## Success Criteria

- Users can select either files or folders without changing the main button label.
- Dropped folders show up in the preview page.
- Directories are visually distinct from files in the preview.
- The send flow still feels lightweight and easy to follow.

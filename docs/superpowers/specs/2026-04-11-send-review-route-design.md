# Send Review Route Design

## Goal

Make the send flow fully explicit and aligned with the Rust send API.

The current draft page should support two destination modes:

- send by short code
- send by nearby receiver ticket

Selecting a nearby receiver must not prefill the code field. The Send button should navigate to a new review route that shows the fully constructed send request details, but does not start the transfer yet.

## Scope

This change is limited to the Flutter `app/` send flow.

In scope:

- Add destination mode state for code vs nearby
- Remove code prefill behavior from nearby selection
- Keep nearby receiver selection as a first-class send destination
- Make `Send` navigate to a new review route
- Render request details on the review route
- Keep the Rust FRB transfer start for a later confirmation step

Out of scope:

- Starting the Rust transfer from the review route
- Changing the Rust send implementation itself
- Changing receiver-side discovery behavior
- Reworking unrelated app navigation

## Proposed Architecture

Keep a single `SendController` as the owner of the send feature lifecycle.

Add explicit draft destination state that mirrors the Rust destination shape:

- `SendDestinationMode.none`
- `SendDestinationMode.code`
- `SendDestinationMode.nearby`

The controller owns the canonical send intent for the draft:

- selected files
- destination mode
- code value, when using code mode
- nearby receiver ticket and label, when using nearby mode

The draft screen becomes a view over that state. It can still host nearby scanning UI, but nearby selection must update the controller instead of pre-filling the code field.

The Send button no longer starts transfer directly. Instead it validates the current draft intent and navigates to a new route that shows the request details.

The controller should build a `SendTransferRequestData`-equivalent object from the current draft state and pass that object into the review route. The review route is only responsible for displaying that request.

## State Model

### Session Phase

Use a small enum for the overall send lifecycle:

- `idle`
- `drafting`
- `reviewing`
- `transferring`
- `result`

### Destination Mode

Use a dedicated destination-mode enum:

- `none`
- `code`
- `nearby`

### Draft Destination State

Represent the current destination with a sealed-style enum or equivalent tagged state:

- code destination:
  - `code`
  - stored short code string
- nearby destination:
  - `nearby`
  - stored `ticket`
  - stored display label
  - optionally stored code for display only, but not as the active destination value

### Nearby Scan State

Nearby scanning should remain explicit, but it does not need to be part of the destination itself.

Use a small enum for scan status:

- `idle`
- `scanning`
- `ready`
- `empty`
- `failed`

Nearby devices themselves remain a list of:

- `fullname`
- `label`
- `code`
- `ticket`

The selected nearby receiver is derived from the draft destination state rather than stored separately on each item.

## Data Flow

### Code path

1. User types a 6-character code.
2. Controller stores the draft destination in `code` mode.
3. The draft screen remains on the current page.
4. The Send button becomes enabled when files exist and the code is valid.
5. Tapping Send navigates to the review route.
6. The review route shows the built request details for code mode.

### Nearby path

1. User scans for nearby receivers.
2. The screen shows nearby receiver tiles.
3. User taps one nearby receiver.
4. Controller stores the draft destination in `nearby` mode with the receiver ticket and label.
5. The code field remains untouched.
6. The Send button becomes enabled when files exist and a nearby receiver is selected.
7. Tapping Send navigates to the review route.
8. The review route shows the built request details for nearby mode.

## Review Route

Add a new route, for example `/send/review`.

The route should accept or read the built `SendTransferRequestData`-equivalent details and render them as a read-only summary.

Show only request details for now:

- destination mode
- code or nearby label, depending on mode
- nearby ticket when relevant
- selected files
- sender device name
- sender device type
- rendezvous server URL, if set

The review route should not:

- start the transfer
- mutate the draft destination
- prefill the code field

## Error Handling

- If no destination is selected, the Send button stays disabled.
- If a nearby receiver is selected but its ticket is missing or malformed, the controller should not navigate to the review route.
- If the typed code is invalid, the Send button stays disabled.
- If the request cannot be built from draft state, the page should remain in drafting state and show a small inline error only if needed.

For now, transport errors are not part of this step because the transfer does not start on the review route yet.

## Testing

Add or update tests to cover:

- Tapping a nearby receiver does not prefill the code field
- Typing a code stores code destination mode
- Tapping a nearby receiver stores nearby destination mode
- The Send button is disabled when there is no valid destination
- Tapping Send navigates to the review route
- The review route renders the request details for code mode
- The review route renders the request details for nearby mode

## Success Criteria

- Nearby selection is explicit and does not write into the code field.
- Code and nearby destinations are mutually exclusive.
- The Send button always leads to a review step instead of starting transfer immediately.
- The review step shows the exact request that will be sent.
- The send flow now mirrors the Rust destination model more closely and is ready for the final transfer-confirmation step.

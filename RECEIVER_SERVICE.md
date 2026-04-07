# Receiver Service Architecture

`ReceiverService` is the public app-layer facade for receiving files. It is split into four roles:

- `ReceiverService`: the API surface used by CLI, Flutter, and tests.
- `ReceiverRuntime`: long-lived mutable state for registration, discoverability, and active offer bookkeeping.
- `run_receiver_actor()`: the command loop that applies state changes and publishes snapshots/events.
- `ReceiverSession`: one incoming connection, from handshake through transfer completion.

## Startup

`ReceiverService::start()`:

1. Binds the iroh endpoint.
2. Creates the command, snapshot, pairing-code, and event channels.
3. Spawns the listener task that accepts incoming connections.
4. Creates `ReceiverRuntime`.
5. Spawns the receiver actor loop.

The public API then exposes:

- `snapshot()`
- `pairing_code()`
- `setup()`
- `ensure_registered()`
- `set_discoverable()`
- `respond_to_offer()`
- `cancel_transfer()`
- `scan_nearby()`
- `shutdown()`

## Runtime Responsibilities

`ReceiverRuntime` owns the service-wide mutable state:

- iroh endpoint
- listener task handle
- rendezvous registration
- pairing-code state
- discoverability / LAN advertising
- whether there is a pending or active offer

It does not do protocol parsing or file-transfer work.

## Incoming Connection Flow

1. The listener loop waits on `endpoint.accept()`.
2. Each accepted connection becomes a new `ReceiverSession`.
3. The session performs the receiver handshake and validates the offer.
4. The session sends `OfferPrepared` back to the actor.
5. The actor records the pending offer in `ReceiverRuntime`.
6. The UI decides accept or decline through `ReceiverService::respond_to_offer()`.
7. If accepted, the session finishes the transfer and forwards progress.
8. The session sends `OfferFinished` when it ends.

## Session Responsibilities

`ReceiverSession` owns one transfer attempt:

- accepted endpoint + connection
- output directory
- sender identity and labels
- command channel back to the actor

It is responsible for:

- running the handshake
- preparing the offer event
- waiting for the user decision
- running the file receive
- emitting progress and final outcome events

## Current Core Dependency

The app receiver path still uses the older core helpers in `crates/core/src/receiver.rs` and `crates/core/src/transfer.rs`.

That means:

- the app-side architecture is now runtime -> session -> run
- the lower-level core receiver implementation is still the existing helper stack
- the protocol and on-the-wire behavior have not changed

## Summary

The current design keeps the receiver service readable by separating:

- service facade
- mutable runtime state
- per-connection session logic
- actor command handling

This makes the receiver side much closer in shape to the new sender architecture, while preserving current behavior.

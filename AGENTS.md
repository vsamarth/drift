# AGENTS.md

Instructions for Codex and other coding agents working in this repository.

## Project Summary

- `drift` is a minimal file transfer tool built on `iroh`.
- The main binaries are `drift` and `drift-server`.
- Keep the implementation lightweight and easy to follow.

## Repository Layout

- `Cargo.toml`, `Cargo.lock`: root Rust workspace for the core CLI/server crates
- `README.md`: project entryway and high-level overview
- `Makefile`: local development and testing helpers
- `crates/core/`: shared transfer, discovery, rendezvous, LAN, and filesystem-planning logic
- `crates/app/`: application layer for send/receive flows and receiver tests
- `crates/cli/`: `drift` CLI binary and supporting library code
- `crates/server/`: `drift-server` rendezvous binary and supporting library code
- `downloads/`: local output directory used in manual testing.

- `flutter/`: Flutter app and Rust-bridge workspace
- `flutter/lib/`: Dart app code, state management, shell UI, and generated FRB bindings
- `flutter/rust/`: Rust-side Flutter bridge crate and API surface
- `flutter/rust_builder/`: native build glue and Cargokit tooling
- `flutter/android/`, `flutter/ios/`, `flutter/macos/`, `flutter/windows/`, `flutter/linux/`, `flutter/web/`: platform targets and generated native project files
- `flutter/test/`, `flutter/integration_test/`, `flutter/test_driver/`: Flutter test suites
- `flutter/README.md`: Flutter app setup and bridge notes

## Working Agreement

- Prefer small, focused changes over broad refactors.
- Preserve the existing CLI behavior unless the task explicitly asks for a change.
- Follow the current code style and keep dependencies minimal.
- When creating commits, use conventional commit format with short messages, such as `fix: handle empty code`.

## Branching

- Follow git-flow branch naming conventions when creating new branches.
- Use `feature/<topic>` for new work, `fix/<topic>` for bug fixes, `hotfix/<topic>` for urgent production fixes, and `release/<version>` for release prep.
- Keep branch names short, lowercase, and kebab-cased, for example `feature/lan-discovery`.
- Prefer branching from the active integration branch for feature and fix work, and from the release branch for hotfix work.

## Commands

- Makefile overview: `make help`
- `make server`: start `drift-server` on `127.0.0.1:8787` for end-to-end pairing tests
- `make receive`: start a receiver and write incoming files to `downloads/`
- `make send-file`: send a single file through the short-code transfer flow
- `make send-dir`: send a directory and verify recursive transfer behavior
- `make send-nearby`: test LAN discovery and mDNS-based sender selection
- Build: `cargo check`
- Test: `cargo test`
- Format: `cargo fmt`
- Run server directly: `cargo run --bin drift-server -- serve --listen 127.0.0.1:8787`
- Send file directly: `DRIFT_RENDEZVOUS_URL=http://127.0.0.1:8787 cargo run -- send -c <CODE> sample.txt`
- Receive file directly: `DRIFT_RENDEZVOUS_URL=http://127.0.0.1:8787 cargo run -- receive <CODE> --out downloads`
- Send on LAN directly: `cargo run -- send --nearby sample.txt`

## When Making Changes

- Update `README.md` if the user-facing workflow changes.
- Add or update tests when behavior changes.
- Call out any assumptions if the repo does not make them obvious.

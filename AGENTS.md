# AGENTS.md

Instructions for Codex and other coding agents working in this repository.

## Project Summary

- `drift` is a minimal file transfer tool built on `iroh`.
- The main binaries are `drift` and `drift-server`.
- Keep the implementation lightweight and easy to follow.

## Repository Layout

- `src/main.rs`: CLI entrypoint for send/receive flows.
- `src/bin/drift-server.rs`: rendezvous server binary.
- `downloads/`: local output directory used in manual testing.

## Working Agreement

- Prefer small, focused changes over broad refactors.
- Preserve the existing CLI behavior unless the task explicitly asks for a change.
- Follow the current code style and keep dependencies minimal.
- When creating commits, use conventional commit format with short messages, such as `fix: handle empty code`.

## Commands

- Makefile overview: `make help`
- Build: `cargo check`
- Test: `cargo test`
- Format: `cargo fmt`
- Run server: `cargo run --bin drift-server -- serve --listen 127.0.0.1:8787`
- Send file: `DRIFT_RENDEZVOUS_URL=http://127.0.0.1:8787 cargo run -- send -c <CODE> sample.txt`
- Receive file: `DRIFT_RENDEZVOUS_URL=http://127.0.0.1:8787 cargo run -- receive <CODE> --out downloads`
- Send on LAN (mDNS picker): `cargo run -- send --nearby sample.txt` or `make send-nearby FILE=sample.txt`

## When Making Changes

- Update `README.md` if the user-facing workflow changes.
- Add or update tests when behavior changes.
- Call out any assumptions if the repo does not make them obvious.

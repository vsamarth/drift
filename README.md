# drift

`drift` is a minimal file transfer tool built on `iroh`.

## Repository layout

- `crates/core`: shared transfer, rendezvous, and server logic
- `crates/cli`: `drift` command-line app
- `crates/server`: `drift-server` rendezvous binary
- `flutter/`: reserved for a future Flutter app

## Default flow

1. Start `drift-server`:

```bash
cargo run -p drift-server -- serve --listen 127.0.0.1:8787
```

2. Create an offer on the sender:

```bash
DRIFT_RENDEZVOUS_URL=http://127.0.0.1:8787 cargo run -p drift -- send sample.txt photos/
```

3. Accept the offer on the receiver:

```bash
DRIFT_RENDEZVOUS_URL=http://127.0.0.1:8787 cargo run -p drift -- receive AB2CD3 --out downloads
```

`drift-server` stores the sender ticket and file manifest briefly so the receiver can review and accept the offer. File data still moves directly over `iroh`.

## Directory transfers

- `drift send` accepts a mix of files and directories.
- Directory inputs are transferred recursively and keep their top-level root names on the receiver.
- File paths are previewed before accept, and the receive step fails if any destination path already exists.
- v1 only transfers regular files. Symbolic links and empty directories are not preserved.

## Manual fallback

```bash
cargo run -p drift -- receive-ticket --out downloads
cargo run -p drift -- send-ticket <ticket> sample.txt photos/
```

## Server selection

`drift` chooses the pairing server in this order:

1. `--server`
2. `DRIFT_RENDEZVOUS_URL`
3. built-in default URL

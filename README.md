# drift

`drift` is a minimal short-code file transfer tool built on `iroh`.

## Repository layout

- `crates/core`: shared discovery, transfer, rendezvous, and server logic
- `crates/cli`: `drift` command-line app
- `crates/server`: `drift-server` rendezvous binary
- `flutter/`: reserved for a future Flutter app

## Default flow

1. Start `drift-server`:

```bash
cargo run -p drift-server -- serve --listen 127.0.0.1:8787
```

2. Start the receiver and note the short code:

```bash
DRIFT_RENDEZVOUS_URL=http://127.0.0.1:8787 cargo run -p drift -- receive --out downloads
```

3. Send files from another terminal:

```bash
DRIFT_RENDEZVOUS_URL=http://127.0.0.1:8787 cargo run -p drift -- send AB2CD3 sample.txt photos/
```

`drift-server` stores the receiver's discovery ticket briefly so the sender can resolve it by short code. After discovery, the peers run a direct `iroh` transfer-control protocol: the sender offers a manifest, the receiver accepts or declines, and file data only starts after accept.

## Directory Transfers

- `drift send` accepts a mix of files and directories.
- Directory inputs are transferred recursively and keep their top-level root names on the receiver.
- The receiver previews the manifest before accepting.
- The receive step fails before transfer if any destination path already exists.
- v1 only transfers regular files. Symbolic links and empty directories are not preserved.

## Server selection

`drift` chooses the pairing server in this order:

1. `--server`
2. `DRIFT_RENDEZVOUS_URL`
3. built-in default URL

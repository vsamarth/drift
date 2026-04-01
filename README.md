# drift

`drift` is a minimal short-code file transfer tool built on `iroh`.

## Features

- Send files with a short code.
- Find nearby devices on the same network and send without typing a code.
- Receive files with a clear accept/decline step before anything is saved.
- Send folders as well as individual files.
- Use the app on desktop or mobile.
- Choose where incoming files are saved.
- Copy the receive code easily when someone else wants to send to you.

## Repository layout

- `crates/core`: shared discovery, transfer, rendezvous, and server logic
- `crates/cli`: `drift` command-line app
- `crates/server`: `drift-server` rendezvous binary
- `flutter/`: Flutter app and Rust bridge workspace

## Default flow

1. Start `drift-server`:

```bash
cargo run -p drift-server -- serve --listen 127.0.0.1:8787
```

2. Start the receiver and note the short code:

```bash
DRIFT_RENDEZVOUS_URL=http://127.0.0.1:8787 cargo run -p drift -- receive --out downloads
```

3. Send files from another terminal (short code is `-c` / `--code`, then paths):

```bash
DRIFT_RENDEZVOUS_URL=http://127.0.0.1:8787 cargo run -p drift -- send -c AB2CD3 sample.txt photos/
```

`drift-server` stores the receiver's discovery ticket briefly so the sender can resolve it by short code. After discovery, the peers run a direct `iroh` transfer-control protocol: the sender offers a manifest, the receiver accepts or declines, and file data only starts after accept.

## LAN discovery (mDNS)

On a local network, `receive` also publishes the **same** iroh ticket via mDNS (`_drift._udp.local.`) while the short code is active, so senders can find nearby receivers without typing the code.

Send with `--nearby` to scan for a few seconds, list receivers, then enter a number to pick one:

```bash
cargo run -p drift -- send --nearby sample.txt
```

Optional: `--nearby-timeout-secs 20` (default `15`). You still need a rendezvous server for the receiver’s short code, but the sender does not use the code when using `--nearby`.

If the machine has no IPv4 default route, LAN advertising is skipped and receive still works via the short code only.

## Directory Transfers

- `drift send` accepts a mix of files and directories.
- Directory inputs are transferred recursively and keep their top-level root names on the receiver.
- The receiver previews the manifest before accepting.
- The receive step fails before transfer if any destination path already exists.
- v1 only transfers regular files. Symbolic links and empty directories are not preserved.

## Makefile helpers
For quick local testing, the root `Makefile` includes `make send-*` wrappers around the `drift send` CLI. Run **`make help`** for a full list. Summary:
- `make server` (start `drift-server`)
- `make receive` (start receiver)
- `make demo-receive` (start receiver with the temporary demo `hello` payload path)
- `make send CODE=AB2CD3 FILE=sample.txt` (same as `send-file` when `CODE` is set; without `CODE`, prints help and exits)
- `make send-file CODE=AB2CD3 FILE=sample.txt` (send one path; uses `send -c …`)
- `make send-files CODE=AB2CD3 FILES="sample.txt photos/"` (send multiple paths)
- `make send-dir CODE=AB2CD3 DIR=photos/` (send a directory)
- `make send-multiple CODE=AB2CD3` (generate 5 x 100MB random files in a temp `tmd/` dir, transfer it, then delete)
- `make send-large CODE=AB2CD3` (generate a 1GB random file in a temp dir, transfer it, then delete)
- `make send-nearby` (LAN mDNS picker; generates a fresh random 10MB file each run; optional `NEARBY_TIMEOUT_SECS=20`)

## Server selection

`drift` chooses the pairing server in this order:

1. `--server`
2. `DRIFT_RENDEZVOUS_URL`
3. built-in default URL

## CLI logging

The `drift` binary logs to **stderr** with `tracing`. Use **structured fields** (pretty text by default, or JSON for pipelines).

- **Format:** `--log-format pretty` (default) or `--log-format json` (one JSON object per line). Override with env `DRIFT_LOG_FORMAT=json`.
- **Filters:** standard `RUST_LOG` (e.g. `RUST_LOG=drift=debug,iroh=info`). If unset, default is `warn` for dependencies and `info` for the `drift` crate; use `-v` / `-vv` for `drift` at `debug` / `trace` without setting `RUST_LOG`.
- **Receive:** manifest and progress lines from `drift-core` still print to **stdout** during the transfer; stderr carries the structured CLI events (`receive.*`, `send.*`).

Example:

```bash
DRIFT_RENDEZVOUS_URL=http://127.0.0.1:8787 \
  cargo run -p drift -- --log-format json send -c AB2CD3 sample.txt 2>send.log
```

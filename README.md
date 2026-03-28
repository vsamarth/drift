# drift

`drift` is a minimal file transfer tool built on `iroh`.

## Default flow

1. Start `drift-server`:

```bash
cargo run --bin drift-server -- serve --listen 127.0.0.1:8787
```

2. Create an offer on the sender:

```bash
DRIFT_RENDEZVOUS_URL=http://127.0.0.1:8787 cargo run -- send sample.txt
```

3. Accept the offer on the receiver:

```bash
DRIFT_RENDEZVOUS_URL=http://127.0.0.1:8787 cargo run -- receive AB2CD3 --out downloads
```

`drift-server` stores the sender ticket and file manifest briefly so the receiver can review and accept the offer. File data still moves directly over `iroh`.

## Manual fallback

```bash
cargo run -- receive-ticket --out downloads
cargo run -- send-ticket <ticket> sample.txt
```

## Server selection

`drift` chooses the pairing server in this order:

1. `--server`
2. `DRIFT_RENDEZVOUS_URL`
3. built-in default URL

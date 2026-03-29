.PHONY: server send receive

SERVER_URL ?= http://127.0.0.1:8787
SERVER_ADDR ?= 127.0.0.1:8787
FILE ?= Cargo.toml
OUT ?= downloads

server:
	cargo run -p drift-server -- serve --listen $(SERVER_ADDR)

send:
	@if [ -z "$(CODE)" ]; then echo "usage: make send CODE=AB2CD3"; exit 1; fi
	DRIFT_RENDEZVOUS_URL=$(SERVER_URL) cargo run -p drift -- send $(CODE) $(FILE)

receive:
	DRIFT_RENDEZVOUS_URL=$(SERVER_URL) cargo run -p drift -- receive --out $(OUT)

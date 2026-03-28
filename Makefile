.PHONY: server send receive

SERVER_URL ?= http://127.0.0.1:8787
SERVER_ADDR ?= 127.0.0.1:8787
FILE ?= Cargo.toml
OUT ?= downloads

server:
	cargo run --bin drift-server -- serve --listen $(SERVER_ADDR)

send:
	DRIFT_RENDEZVOUS_URL=$(SERVER_URL) cargo run --bin drift -- send $(FILE)

receive:
	@if [ -z "$(CODE)" ]; then echo "usage: make receive CODE=AB2CD3"; exit 1; fi
	DRIFT_RENDEZVOUS_URL=$(SERVER_URL) cargo run --bin drift -- receive $(CODE) --out $(OUT)

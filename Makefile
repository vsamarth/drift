.PHONY: help check test fmt fmt-check clippy server send send-file send-dir send-files send-nearby send-multiple send-large receive demo-receive

SERVER_URL ?= http://127.0.0.1:8787
SERVER_ADDR ?= 127.0.0.1:8787
FILE ?= Cargo.toml
DIR ?=
OUT ?= downloads
FILES ?= $(FILE)

# Synthetic file generation sizes for the send-multiple/send-large targets (overridable).
MULTIPLE_COUNT ?= 5
MULTIPLE_SIZE_MB ?= 100
LARGE_SIZE_MB ?= 1024
NEARBY_SIZE_MB ?= 10

# mDNS scan duration for send-nearby (seconds).
NEARBY_TIMEOUT_SECS ?= 15

help:
	@echo "Drift Makefile targets"
	@echo ""
	@echo "Rust workflow:"
	@echo "  check           — cargo check"
	@echo "  test            — cargo test"
	@echo "  fmt             — cargo fmt"
	@echo "  fmt-check       — cargo fmt --check"
	@echo "  clippy          — cargo clippy --all-targets --all-features"
	@echo ""
	@echo "  server          — drift-server on $(SERVER_ADDR) (override SERVER_ADDR)"
	@echo "  receive         — receiver → $(OUT)/ (override OUT; SERVER_URL for rendezvous)"
	@echo "  demo-receive    — demo hello receiver → $(OUT)/ (override OUT; SERVER_URL for rendezvous)"
	@echo "Send via short code (receiver must show CODE):"
	@echo "  send-file       — CODE=… FILE=…"
	@echo "  send-files      — CODE=… FILES=\"path1 path2\""
	@echo "  send-dir        — CODE=… DIR=path/"
	@echo "  send-multiple   — CODE=…  (temp dir of $(MULTIPLE_COUNT) x $(MULTIPLE_SIZE_MB)MB files)"
	@echo "  send-large      — CODE=…  (temp $(LARGE_SIZE_MB)MB file)"
	@echo "  send            — same as send-file if CODE is set; else prints this help"
	@echo ""
	@echo "Send via LAN (mDNS; receiver must run receive on same network):"
	@echo "  send-nearby     — generates a fresh $(NEARBY_SIZE_MB)MB random file; NEARBY_TIMEOUT_SECS=$(NEARBY_TIMEOUT_SECS)"
	@echo ""
	@echo "Env: SERVER_URL=$(SERVER_URL)"

check:
	cargo check

test:
	cargo test

fmt:
	cargo fmt

fmt-check:
	cargo fmt --check

clippy:
	cargo clippy --all-targets --all-features

server:
	cargo run -p drift-server -- serve --listen $(SERVER_ADDR)

# With CODE: delegates to send-file. Without CODE: lists send targets (see help).
send:
ifndef CODE
	@$(MAKE) help
	@exit 1
else
	@$(MAKE) send-file
endif

send-file:
	@if [ -z "$(CODE)" ]; then echo "usage: make send-file CODE=AB2CD3 FILE=path"; exit 1; fi
	DRIFT_RENDEZVOUS_URL=$(SERVER_URL) cargo run -p drift -- send -c "$(CODE)" "$(FILE)"

send-dir:
	@if [ -z "$(CODE)" ]; then echo "usage: make send-dir CODE=AB2CD3 DIR=photos/"; exit 1; fi
	@if [ -z "$(DIR)" ]; then echo "usage: make send-dir CODE=AB2CD3 DIR=photos/"; exit 1; fi
	DRIFT_RENDEZVOUS_URL=$(SERVER_URL) cargo run -p drift -- send -c "$(CODE)" "$(DIR)"

send-files:
	@if [ -z "$(CODE)" ]; then echo "usage: make send-files CODE=AB2CD3 FILES=\"path1 path2\""; exit 1; fi
	DRIFT_RENDEZVOUS_URL=$(SERVER_URL) cargo run -p drift -- send -c "$(CODE)" $(FILES)

send-nearby:
	@set -e; \
		TMP_DIR=$$(mktemp -d); \
		NEARBY_FILE="$$TMP_DIR/nearby-$$(date +%s)-$$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 8).bin"; \
		trap 'rm -rf "$$TMP_DIR"' EXIT INT TERM; \
		echo "Generating $$NEARBY_FILE ($(NEARBY_SIZE_MB)MB) ..."; \
		dd if=/dev/urandom of="$$NEARBY_FILE" bs=1m count="$(NEARBY_SIZE_MB)" status=none 2>/dev/null || \
		dd if=/dev/urandom of="$$NEARBY_FILE" bs=1m count="$(NEARBY_SIZE_MB)" >/dev/null 2>&1; \
		DRIFT_RENDEZVOUS_URL=$(SERVER_URL) cargo run -p drift -- send --nearby --nearby-timeout-secs $(NEARBY_TIMEOUT_SECS) "$$NEARBY_FILE"

send-multiple:
	@if [ -z "$(CODE)" ]; then echo "usage: make send-multiple CODE=AB2CD3"; exit 1; fi
	@set -e; \
		TMP_DIR=$$(mktemp -d); \
		TMD_DIR="$$TMP_DIR/tmd"; \
		trap 'rm -rf "$$TMP_DIR"' EXIT INT TERM; \
		mkdir -p "$$TMD_DIR"; \
		i=1; \
		while [ $$i -le $(MULTIPLE_COUNT) ]; do \
			F="$$TMD_DIR/file-$$i.bin"; \
			echo "Generating $$F ($(MULTIPLE_SIZE_MB)MB) ..."; \
			dd if=/dev/urandom of="$$F" bs=1m count="$(MULTIPLE_SIZE_MB)" status=none 2>/dev/null || \
			dd if=/dev/urandom of="$$F" bs=1m count="$(MULTIPLE_SIZE_MB)" >/dev/null 2>&1; \
			i=$$((i+1)); \
		done; \
		DRIFT_RENDEZVOUS_URL=$(SERVER_URL) cargo run -p drift -- send -c "$(CODE)" "$$TMD_DIR"

send-large:
	@if [ -z "$(CODE)" ]; then echo "usage: make send-large CODE=AB2CD3"; exit 1; fi
	@set -e; \
		TMP_DIR=$$(mktemp -d); \
		LARGE_FILE="$$TMP_DIR/large.bin"; \
		trap 'rm -rf "$$TMP_DIR"' EXIT INT TERM; \
		echo "Generating $$LARGE_FILE ($(LARGE_SIZE_MB)MB) ..."; \
		dd if=/dev/urandom of="$$LARGE_FILE" bs=1m count="$(LARGE_SIZE_MB)" status=none 2>/dev/null || \
		dd if=/dev/urandom of="$$LARGE_FILE" bs=1m count="$(LARGE_SIZE_MB)" >/dev/null 2>&1; \
		DRIFT_RENDEZVOUS_URL=$(SERVER_URL) cargo run -p drift -- send -c "$(CODE)" "$$LARGE_FILE"

receive:
	DRIFT_RENDEZVOUS_URL=$(SERVER_URL) cargo run -p drift -- receive --out "$(OUT)"

demo-receive:
	DRIFT_DEMO_HELLO=1 DRIFT_RENDEZVOUS_URL=$(SERVER_URL) cargo run -p drift -- receive --out "$(OUT)"

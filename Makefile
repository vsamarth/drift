.PHONY: server send receive send-file send-dir send-files send-multiple send-large

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

server:
	cargo run -p drift-server -- serve --listen $(SERVER_ADDR)

send:
	@$(MAKE) send-file

send-file:
	@if [ -z "$(CODE)" ]; then echo "usage: make send-file CODE=AB2CD3 FILE=path"; exit 1; fi
	DRIFT_RENDEZVOUS_URL=$(SERVER_URL) cargo run -p drift -- send $(CODE) $(FILE)

send-dir:
	@if [ -z "$(CODE)" ]; then echo "usage: make send-dir CODE=AB2CD3 DIR=photos/"; exit 1; fi
	DRIFT_RENDEZVOUS_URL=$(SERVER_URL) cargo run -p drift -- send $(CODE) $(DIR)

send-files:
	@if [ -z "$(CODE)" ]; then echo "usage: make send-files CODE=AB2CD3 FILES=\"path1 path2\""; exit 1; fi
	@if [ -z "$(FILES)" ]; then echo "usage: make send-files CODE=AB2CD3 FILES=\"path1 path2\""; exit 1; fi
	DRIFT_RENDEZVOUS_URL=$(SERVER_URL) cargo run -p drift -- send $(CODE) $(FILES)

send-multiple:
	@if [ -z "$(CODE)" ]; then echo "usage: make send-multiple CODE=AB2CD3"; exit 1; fi
	@set -e; \
		TMP_DIR=$$(mktemp -d -t drift-send-multiple-XXXXXX); \
		TMD_DIR="$$TMP_DIR/tmd"; \
		trap 'rm -rf "$$TMP_DIR"' EXIT INT TERM; \
		mkdir -p "$$TMD_DIR"; \
		i=1; \
		while [ $$i -le $(MULTIPLE_COUNT) ]; do \
			F="$$TMD_DIR/file-$$i.bin"; \
			echo "Generating $$F ($(MULTIPLE_SIZE_MB)MB) ..."; \
			dd if=/dev/urandom of="$$F" bs=1m count="$(MULTIPLE_SIZE_MB)" > /dev/null 2>&1; \
			i=$$((i+1)); \
		done; \
		DRIFT_RENDEZVOUS_URL=$(SERVER_URL) cargo run -p drift -- send $(CODE) "$$TMD_DIR"

send-large:
	@if [ -z "$(CODE)" ]; then echo "usage: make send-large CODE=AB2CD3"; exit 1; fi
	@set -e; \
		TMP_DIR=$$(mktemp -d -t drift-send-large-XXXXXX); \
		FILE="$$TMP_DIR/large-1gb.bin"; \
		trap 'rm -rf "$$TMP_DIR"' EXIT INT TERM; \
		echo "Generating $$FILE ($(LARGE_SIZE_MB)MB) ..."; \
		dd if=/dev/urandom of="$$FILE" bs=1m count="$(LARGE_SIZE_MB)" > /dev/null 2>&1; \
		DRIFT_RENDEZVOUS_URL=$(SERVER_URL) cargo run -p drift -- send $(CODE) "$$FILE"

receive:
	DRIFT_RENDEZVOUS_URL=$(SERVER_URL) cargo run -p drift -- receive --out $(OUT)

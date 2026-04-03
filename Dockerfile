# Stage 1: Build
FROM rust:1.81-slim AS builder

WORKDIR /usr/src/drift
COPY . .

# Build the server package
RUN cargo build --release -p drift-server

# Stage 2: Runtime
FROM debian:bookworm-slim

WORKDIR /app

# Install necessary libraries (like OpenSSL if needed)
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*

# Copy the binary from the builder stage
COPY --from=builder /usr/src/drift/target/release/drift-server /app/drift-server

EXPOSE 8787

# Run the server
CMD ["/app/drift-server", "serve", "--listen", "0.0.0.0:8787"]

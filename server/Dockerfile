# Build frontend
FROM node:20-alpine AS frontend

WORKDIR /app/web
COPY web/package*.json ./
RUN npm ci
COPY web/ ./
RUN npm run build

# Build logbook viewer (E2E sync SPA). The vendored cw-web-crypto wasm pkg is
# committed under logbook-web/vendor, so the `file:` dep resolves offline.
FROM node:20-alpine AS logbook
WORKDIR /app/logbook-web
COPY logbook-web/ ./
RUN npm ci
RUN npm run build

# Build Rust backend
FROM rust:1.88-alpine AS builder

WORKDIR /app

# Install build dependencies
RUN apk add --no-cache musl-dev

# Copy manifests
COPY Cargo.toml Cargo.lock ./

# Create dummy main.rs for dependency caching
RUN mkdir src && echo "fn main() {}" > src/main.rs

# Build dependencies only
RUN cargo build --release && rm -rf src

# Copy actual source
COPY src ./src
COPY migrations ./migrations

# Build the application
RUN touch src/main.rs && cargo build --release

# Runtime image
FROM alpine:3.19

WORKDIR /app

RUN apk add --no-cache ca-certificates

COPY --from=builder /app/target/release/challenges-server /usr/local/bin/
COPY --from=frontend /app/web/dist ./web/dist
COPY --from=logbook /app/logbook-web/dist ./logbook-web/dist

EXPOSE 8080

CMD ["challenges-server"]

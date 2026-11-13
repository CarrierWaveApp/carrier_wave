FROM rust:1.85-bookworm AS builder

WORKDIR /build

# Cache dependencies by building a dummy project first
COPY Cargo.toml Cargo.lock ./
COPY sdr-core/Cargo.toml sdr-core/Cargo.toml
COPY sdr-server/Cargo.toml sdr-server/Cargo.toml
COPY sdr-cli/Cargo.toml sdr-cli/Cargo.toml
RUN mkdir -p sdr-core/src sdr-server/src sdr-cli/src \
    && echo "fn main() {}" > sdr-server/src/main.rs \
    && echo "fn main() {}" > sdr-cli/src/main.rs \
    && echo "" > sdr-core/src/lib.rs \
    && cargo build --release 2>/dev/null || true \
    && rm -rf sdr-core/src sdr-server/src sdr-cli/src

# Build the real project
COPY sdr-core sdr-core
COPY sdr-server sdr-server
COPY sdr-cli sdr-cli
RUN touch sdr-core/src/lib.rs sdr-server/src/main.rs sdr-cli/src/main.rs \
    && cargo build --release

FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /build/target/release/sdr-server /usr/local/bin/sdr-server

RUN useradd --create-home --shell /bin/bash sdr \
    && mkdir -p /home/sdr/data \
    && chown sdr:sdr /home/sdr/data
USER sdr
WORKDIR /home/sdr

EXPOSE 8080

ENTRYPOINT ["sdr-server"]
CMD ["config.toml"]

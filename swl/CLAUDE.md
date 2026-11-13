# CW SWL

SDR recording server for CW shortwave listening — multi-receiver IQ recording, demodulation, CW transcription, and audio serving via REST API.

## Architecture

Rust workspace with three crates:

```
swl/
├── sdr-core/          # Core library
│   ├── src/api/       # Axum route handlers
│   ├── src/db/        # SQLite models and queries
│   ├── src/sdr/       # SDR drivers (KiwiSDR, SoapySDR, mock)
│   ├── src/recording/ # DSP, FLAC encoding, segment management
│   ├── src/mux/       # Multiplexer for shared SDR access
│   └── src/transcription/  # CW decoder (Goertzel, beam search, HSMM, ensemble)
├── sdr-server/        # Axum HTTP server binary
├── sdr-cli/           # CLI tool for direct SDR interaction
├── web/               # Web UI (React/TypeScript/Vite)
├── tools/             # Helper scripts (SDR picker, audio scrubber)
└── docs/              # Configuration, plans, research
```

## Building and Testing

```bash
cargo build              # Build all crates
cargo test               # Run tests
cargo run -p sdr-server  # Run recording server
cargo run -p sdr-cli     # Run CLI tool
```

Configuration via TOML file. See [docs/configuration.md](docs/configuration.md) and `examples/config.toml`.

## Deployment

Deployed via Ansible role `cw_swl` in `infra/ansible/`. Uses Docker (`Dockerfile` + `docker-compose.yml`).

## Key Docs

| Area | Details |
|------|---------|
| Configuration | [docs/configuration.md](docs/configuration.md) |
| CW Decoder Research | [docs/research/2026-02-21-cw-decoder-algorithms.md](docs/research/2026-02-21-cw-decoder-algorithms.md) |
| Transcription Tuning | [docs/transcription-tuning-log.md](docs/transcription-tuning-log.md) |

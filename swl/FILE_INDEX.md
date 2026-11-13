# CW SWL File Index

SDR recording server (Rust workspace: sdr-core, sdr-cli, sdr-server + web UI).

## sdr-core/src/

| file | purpose |
|------|---------|
| `lib.rs` | Library module exports |
| `config.rs` | Config struct and TOML parsing |
| `error.rs` | Error types |
| `types.rs` | Shared type definitions (SDR, recording, band) |
| `time.rs` | Timestamp provider for synchronized timing |

## sdr-core/src/api/

| file | purpose |
|------|---------|
| `health.rs` | Health check endpoints |
| `transcriptions.rs` | Transcription query and export endpoints |

## sdr-core/src/db/

| file | purpose |
|------|---------|
| `mod.rs` | SQLite connection and initialization |
| `models.rs` | Row types for SQLite queries |
| `queries.rs` | Async SQL queries (recordings, segments, transcriptions) |

## sdr-core/src/sdr/

| file | purpose |
|------|---------|
| `discovery.rs` | SDR device discovery and registry |
| `kitty.rs` | KiwiSDR network SDR driver |
| `soapy.rs` | SoapySDR USB receiver driver |
| `mock.rs` | Mock SDR for testing |

## sdr-core/src/mux/

| file | purpose |
|------|---------|
| `mod.rs` | Multiplexer task and message routing |
| `request.rs` | Capture request types |
| `session.rs` | Consumer session and handle types |

## sdr-core/src/recording/

| file | purpose |
|------|---------|
| `mod.rs` | Recording engine and segment management |
| `audio_decode.rs` | Audio demodulation from IQ samples |
| `dsp.rs` | DSP filters and frequency shifting |
| `segment.rs` | Recording segment metadata and tracking |
| `combine.rs` | Combine multiple segment recordings |
| `flac.rs` | FLAC audio encoding |

## sdr-core/src/transcription/

| file | purpose |
|------|---------|
| `mod.rs` | Transcription engine orchestrator |
| `decoder.rs` | Main CW decoder (Goertzel multi-frequency) |
| `decoder_a.rs` | Alternative decoder implementation |
| `decoder_trait.rs` | Decoder trait abstraction |
| `morse.rs` | Morse code symbol lookup and validation |
| `tone_detector.rs` | Tone detection and filtering |
| `quadrature.rs` | Quadrature demodulation |
| `beam.rs` | Beam search decoder for symbol sequences |
| `hsmm.rs` | Hidden semi-Markov model decoder |
| `ensemble.rs` | Ensemble voting across multiple decoders |
| `language_model.rs` | Language model for word inference |
| `postprocess.rs` | Post-decode cleanup and correction |
| `legacy.rs` | Legacy decoder (deprecated) |
| `structured.rs` | Structured data extraction from CW |

## Binaries

| path | purpose |
|------|---------|
| `sdr-cli/src/main.rs` | CLI tool for direct SDR control and testing |
| `sdr-server/src/main.rs` | HTTP server entry point and task spawner |

## Web UI (`web/src/`)

| path | purpose |
|------|---------|
| `main.tsx` | Vite entry point |
| `App.tsx` | Root component |
| `api/` | API client and types |
| `components/` | React components (status, maps, filters) |
| `hooks/` | Custom React hooks (API queries) |
| `pages/` | Page-level components |
| `styles/` | CSS and design tokens |
| `utils/` | Utility functions |

## Tools / Examples

| path | purpose |
|------|---------|
| `tools/pick-sdrs.py` | SDR discovery and selection script |
| `tools/record-trio.sh` | Multi-receiver recording orchestration |
| `tools/scrubber.html` | Web UI for audio review and QC |
| `examples/config.toml` | Example configuration file |

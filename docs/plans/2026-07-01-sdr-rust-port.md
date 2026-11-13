# SDR Selection + Listening → Rust, Swift swap, Web spots page

Date: 2026-07-01 · Branch: `worktree-sdr-rust-port`

## Decisions (user-confirmed)

1. **FFI boundary:** Rust (cw-net) owns the KiwiSDR websocket protocol — handshake, tuning,
   keepalive, MSG parsing — and IMA ADPCM decode. Decoded PCM Int16 frames stream to Swift via
   a UniFFI callback trait. Swift keeps only the ring buffer + AVAudioEngine playback (+ recorder).
2. **Scope:** everything in one pass — directory, status enrichment, all three TuneIn strategies
   (`nearStrongRBN`, `nearActivator`, `nearMyQTH`), and SmartFeatures (QSY detection/retune,
   receiver quality monitoring, follow-activator).
3. **Web home:** new Spots page in `server/logbook-web` (already has Vite + Rust WASM pattern).
4. **Web audio:** JS WebSocket transport + AudioWorklet playback; shared Rust ADPCM decoder,
   mode/passband tables, and receiver ranking compiled to WASM alongside `cw-web-crypto`.

## Phases

| # | Phase | Where |
|---|-------|-------|
| 1 | Domain logic: modes/passbands, ADPCM, directory/status parsing, ranking, QSY/quality logic | `rust/cw-core/cw-domain/src/kiwisdr/` |
| 2 | Network: directory fetch, /status fetcher, websocket SND client (tokio-tungstenite) | `rust/cw-core/cw-net/src/kiwisdr.rs` |
| 3 | FFI: async `SdrApi` + `PcmFrameListener` callback, modeled on FriendsApi/SessionApi | `rust/cw-core/cw-ffi/src/sdr_api.rs` |
| 4 | Swift swap: WebSDRDirectory/KiwiSDRClient/TuneInManager delegate to FFI | `swift/ios/CarrierWave/Services/WebSDR/` |
| 5 | Web: Spots page + KiwiSDR listen (WASM decode exports, AudioWorklet) | `server/logbook-web/`, `rust/cw-core/cw-web-crypto/` (or sibling wasm crate) |
| 6 | Gates: cargo build/clippy/test (no fmt), swiftformat/lint, xc build, web build, changelog | — |

## Parity bar

Per `rust-swift-parity`: Rust port must reach full behavioral parity with the Swift
implementation; parity tests are the acceptance bar (fixture tests for ADPCM, ranking,
antenna/status parsing). Swift sources under `Services/WebSDR/` are the spec.

## Known gotchas

- KiwiSDR sends `MSG` text inside binary frames (KiwiSDRClient.swift:203).
- `MSG too_busy=0` is NOT a disconnect (memory: kiwisdr-too-busy).
- `cw-web-crypto` is its own workspace (wasm32 getrandom `js` feature) — SDR WASM exports go
  there or in a sibling crate, not in the cw-core workspace.
- Real-time PCM over FFI: batch frames (~decoded packet granularity), never per-sample calls.

# cw-core — Carrier Wave portable Rust core

Cross-platform Rust core (query language, FT8, SQLCipher store, net clients,
sync, UniFFI surface) consumed by the Apple apps via UniFFI and by `android/`
via Kotlin bindings.

> Read [`README.md`](README.md) for the crate map, build/test commands, and the
> Swift consumption flow. Load [`FILE_INDEX.md`](FILE_INDEX.md) before exploring
> source.

## Conventions

- **Hand-formatted — do NOT run `cargo fmt`.** It produces enormous churn. Match
  surrounding style by hand. The quality gate is **build + clippy + test**, not fmt.
- Clippy runs `-D warnings` on `--all-targets` in CI; keep new code clean.
- The FFI surface lives **only** in `cw-ffi`; nothing else is `pub` across the
  language boundary.
- Bounded queries are enforced at the store (`MAX_FETCH_LIMIT`), not just the UI.
- Ports are **faithful**: each module names the Swift source it mirrors and
  parity tests are the acceptance bar — no quiet subset or fallback.

## Testing

```bash
cargo test --workspace                 # default suite (durability tests are NOT included — see below)
cargo clippy --workspace --all-targets -- -D warnings
```

Write-durability torture tests (`cw-store`) live behind the `testing` cargo
feature and are documented in
[README.md → Write-durability torture tests](README.md#write-durability-torture-tests):

```bash
cargo test -p cw-store --features testing --test durability -- --test-threads=1
```

`--test-threads=1` is required for the fsync-heavy fault tests. The Swift-layer
durability tests build `LogDurabilityCrasher` then run `swift test --filter
LogDurabilityTests` from `swift/packages/CarrierWaveCore/` (see the README).

# cw-core — Carrier Wave portable Rust core

Cross-platform core extracted from the Apple-only Swift packages, per
[`docs/plans/2026-06-13-rust-core-migration.md`](../../docs/plans/2026-06-13-rust-core-migration.md).
Consumed by Swift today via UniFFI; the same compiled library targets
Android/desktop later.

## Crates

| Crate | Phase | What it is | Status |
|-------|-------|------------|--------|
| `cw-domain` | 0, 2 | Query language (lexer/parser/AST/analyzer), band/mode/service-type/Maidenhead, formatters, antenna patterns, azimuthal projection, TOTA scoring + detectors, QSO dedup + two-fer matchers, park-reference helpers, streak calculator, NATO phonetics, CW text elements, US band plan, IARU region, DXCC primary-prefix table, embedded Natural Earth coastlines (`data/coastline.json`) | ✅ ported + tested (215 tests; Phase 2 closed on the Rust side) |
| `cw-ft8` | 1 | FT8 decoder/encoder + WAV loader (wraps vendored `ft8_lib`) | ✅ decoder + encoder + WAV-fixture parity tested |
| `cw-store` | 4 | SQLCipher (encrypted-at-rest) store, schema/migrations, bounded query API; all 13 synced entities modelled (QSO + LoggingSession, ServicePresence, SessionSpot, ActivationMetadata, ActivityLog, EquipmentItem, RadioMacro, WebSDRRecording, WebSDRFavorite, UploadDestination, CloudSyncMetadata) | ✅ entities + bounded CRUD tested; ⏳ SwiftData→SQLite importer + consumer cutover |
| `cw-net` | 3 | Spot/API wire models, parsers, and async reqwest transports for POTA/SOTA/WWFF/PSKReporter/DONKI/HamQSL/LoFi | ✅ ported + tested (38 tests, PSK rate-limit + DONKI/HamQSL caches mirror Swift) |
| `cw-sync` | 5 | Change journal, conflict resolution, transport trait | ✅ logic tested; ⏳ HTTPS server transport |
| `cw-ffi` | 0 | The single UniFFI surface (query + maidenhead + `FieldStore` with all 13 entities' CRUD + the `StoreObserver` change-callback bridge + the `WsjtxApi` UDP listener / `WsjtxListenerDelegate` event bridge) | ✅ Swift XCFramework + Kotlin bindings shipping; consumed by `CarrierWaveCore` + `android/` |

## Build & test

```bash
cargo test --workspace                # 342 tests across all crates (incl. the observation-API callback tests)
cargo clippy --workspace --all-targets
cargo build -p cw-ffi                 # produces target/debug/libcw_ffi.{so,dylib,a}
./scripts/build-xcframework.sh        # CwFfi.xcframework + Swift bindings, staged into CarrierWaveCore
```

`cw-store`/`cw-ffi` compile SQLCipher + OpenSSL from source on first build
(`bundled-sqlcipher-vendored-openssl`), so the first build is slow (~90s) and
self-contained on every platform. The XCFramework script cross-compiles for
four Apple targets (iOS device/sim, macOS arm64/x86_64) so first run is ~6
minutes; subsequent runs are seconds.

## Write-durability torture tests

`cw-store` carries a torture suite that proves the QSO logbook's write
invariant — **once `upsert_qso` returns `Ok`, that QSO survives every
disruption present and field-for-field intact, and the DB always reopens
clean** — under power loss, torn pages, disk-full, app crash, and concurrent
writers. The faults are injected by a custom crash-injection SQLite VFS
(`src/testing/crash_vfs.rs`) layered under SQLCipher. See the design notes in
[`docs/plans/2026-06-20-log-write-durability-torture-test-design.md`](../../docs/plans/2026-06-20-log-write-durability-torture-test-design.md).

The suite and its VFS live behind the `testing` cargo feature, so a normal
`cargo test --workspace` / release build never compiles them. Run it
explicitly:

```bash
# Whole suite: power-loss, torn-page, ENOSPC, app-crash, concurrency, CRUD-through-VFS.
# --test-threads=1 is required: the fsync-heavy fault tests saturate disk and
# trip false SQLITE_BUSY if run in parallel (CI uses this flag too).
cargo test -p cw-store --features testing --test durability -- --test-threads=1

# A single fault:
cargo test -p cw-store --features testing --test durability power_loss_preserves_all_acked_qsos

# Exhaustive crash-point walk (slow; default caps the power-loss loop at ~200 points):
CW_DURABILITY_EXHAUSTIVE=1 cargo test -p cw-store --features testing \
    --test durability power_loss_preserves_all_acked_qsos -- --test-threads=1
```

The Swift layer re-proves the ack boundary (app-crash) and concurrency through
the UniFFI `FieldStore` bindings. The test target can't depend on the crasher
executable, so build it first (needs the staged xcframework — run
`./scripts/build-xcframework.sh` if `Vendored/CwFfi.xcframework` is missing):

```bash
# from swift/packages/CarrierWaveCore/
swift build --product LogDurabilityCrasher
swift test --filter LogDurabilityTests
```

CI wires both: the Linux `test` job runs the Rust suite with `--features
testing`, and the macOS `xcframework` job builds the crasher and runs
`LogDurabilityTests`.

## Consuming from Swift

`build-xcframework.sh` stages two gitignored artifacts into
`swift/packages/CarrierWaveCore/`:

| Artifact | Path | Wired by |
|---|---|---|
| `CwFfi.xcframework` (3 slices) | `Vendored/CwFfi.xcframework` | `Package.swift` binary target |
| `CwFfi+Generated.swift` (UniFFI bindings) | `Sources/CarrierWaveCwFfi/` | `Package.swift` Swift target |

`CarrierWaveCore` depends on `CarrierWaveCwFfi`; Swift code calls
`QueryAnalyzer.analyzeViaRust(_:qsoCount:)` (see
`QueryAnalyzer+Rust.swift`). Parity vs. the legacy Swift analyzer is asserted
by `QueryAnalyzerRustParityTests`.

Store reactivity (the SwiftData `@Query` replacement) flows through
`FieldStore.changes(for:)` in `FieldStore+Observation.swift`: it adapts the
Rust `StoreObserver` callback into an `AsyncStream<FfiStoreChange>` a view drives
`.task` re-fetches from. Rust fires the callback with the DB lock released, so an
observer can re-fetch without deadlock (asserted in cw-ffi's
`callback_can_reenter_store_without_deadlock`). All 12 store entities fire
`notify(...)` from their upsert; deletes are not yet exposed over the FFI.

## What is NOT done here (by design / environment)

- **The FT8 C decoder** — `ft8_lib` is already vendored at
  `swift/packages/CarrierWaveCore/Sources/CFT8`; binding it is a `cc`/`bindgen`
  step gated on the WAV-fixture parity harness.
- **Live network exercise of `cw-net`** — every transport compiles and is
  unit-tested for parsing, rate-limit, and cache logic, but the actual HTTP
  hits against POTA/SOTA/WWFF/PSK/DONKI/HamQSL/LoFi happen once `cw-ffi`
  exposes them to the iOS/macOS apps.
- **HTTPS sync server** (`cw-sync`) — journal/conflict logic is ported and
  tested; the server-side transport is still a documented seam.
- **Consumer decoupling** — replacing SwiftData across the 370+ Apple-side files
  is the bulk of Phase 4 and is human/Xcode work tracked in the plan.
- **CI for the XCFramework** — `build-xcframework.sh` is local-only today;
  Xcode Cloud gating of the Rust path is still pending.

## Conventions

- Ports are **faithful**: each module names the Swift source it mirrors and
  preserves its observable behavior (tests assert parity semantics).
- The FFI surface lives **only** in `cw-ffi`; nothing else is `pub` across the
  language boundary.
- Bounded queries are enforced at the store (`MAX_FETCH_LIMIT`), not just the UI.

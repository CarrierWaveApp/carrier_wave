# Rust Core Migration — Handoff

**Date:** 2026-06-13
**Branch:** `claude/carrier-wave-cross-platform-mhvudp`
**Companion docs:** [migration plan](2026-06-13-rust-core-migration.md) · [`rust/cw-core/README.md`](../../rust/cw-core/README.md) · [`rust/cw-core/FILE_INDEX.md`](../../rust/cw-core/FILE_INDEX.md)

This is the "pick it up from here" doc. The plan explains *why* and *what*; this
explains *what's done, what's next, and what's blocked on environment*.

---

## TL;DR

A real `rust/cw-core/` workspace exists with **342 passing tests**
(`cargo test --workspace`), clippy-clean. The Phase-0 toolchain bet (Rust →
UniFFI → consumed behind today's Swift APIs) is **closed end-to-end on
2026-06-13**: `CwFfi.xcframework` builds, `CarrierWaveCore` consumes it through
SPM, and `QueryAnalyzerRustParityTests` (11 vectors) asserts Swift↔Rust
agreement on every observable field.

**Phase 1 (FT8), Phase 2 (pure domain), and Phase 3 (network) are all
closed on the Rust side as of 2026-06-13.** Reference data (DXCC primary
prefixes, US FCC band plan, Natural Earth coastlines) is canonicalized into
`cw-domain`.

**Phase 4 progress (2026-06-14):** all **13 entities are modelled in `cw-store`**
(bounded CRUD, 59 tests) **and exposed over `cw-ffi`** (`entities/*.rs`, Swift +
Kotlin bindings regenerate cleanly). A second consumer — the **`android/`**
Compose app — runs the unchanged core on-device (Phase 6 spiked early). The
**observation API — the flagged risk — is now prototyped** (2026-06-14): a
foreign-implementable `StoreObserver` callback, a token-keyed registry on
`FieldStore`, `notify` fired **with the DB lock released** so a Swift observer can
re-fetch from inside its own callback without deadlocking (proven by a Rust
re-entry test), and a Swift `FieldStore.changes(for:)` → `AsyncStream` adapter.
**All 12 store entities now fire `notify(...)` from their upsert** (2026-06-14);
deletes aren't exposed over the FFI yet. The remaining Phase 4 work is (a) the
**one-time SwiftData→SQLite importer**, and (b) the big one — decoupling
SwiftData from 370+ Apple-side files. CI gating of the cross-language path is
also still open.

> **▶ NEXT SESSION:** the **SwiftData→SQLite importer is built + unit-tested + on
> device** (manual Settings trigger), pending on-device success confirmation —
> see [importer design + progress](2026-06-14-swiftdata-import-design.md). QSO was
> expanded to full fidelity ([audit](2026-06-14-cw-store-fidelity-audit.md)). Once
> the on-device import is confirmed clean, the remaining Phase-4 work is the
> **entity-by-entity consumer cutover** (replace `@Query`/reads with the Rust
> store behind a flag — the months-long epic). (Nice to have alongside: a Swift
> parity test that drives `changes(for:)` on device/sim, and exposing entity
> deletes so `notify` can emit `Delete`.)

Locked decisions (don't relitigate): full data layer into Rust · UniFFI
Swift-first · SQLCipher at rest · single identity w/ OAuth2 access+refresh ·
reference data canonicalized into the Rust repo · RemoteOp schema in `cw-domain`
· macOS Sweep migrates lockstep with iOS.

## Verify the current state

```bash
cd rust/cw-core
cargo test --workspace                # 342 tests (incl. the observation-API callback tests)
cargo clippy --workspace --all-targets
cargo build -p cw-ffi                 # libcw_ffi.{so,dylib,a}
./scripts/build-xcframework.sh        # CwFfi.xcframework + Swift bindings, staged

cd ../../swift/packages/CarrierWaveCore
swift test --filter QueryAnalyzerRustParityTests  # Swift↔Rust parity gate
swift test --filter FieldStoreObservationTests    # observation API across the FFI boundary
```
First Rust build is ~90s (compiles SQLCipher + OpenSSL from source). First
XCFramework build is ~6 minutes (vendored OpenSSL × 4 Apple slices); subsequent
runs only rebuild what changed. Per-crate status is the table in
`rust/cw-core/README.md`.

---

## Next steps, in priority order

### 1. ✅ Close the Phase-0 loop on the Swift side — DONE 2026-06-13
The toolchain bet is proven. What landed:
- `cw-ffi` gained a library-mode `uniffi-bindgen` binary target. UniFFI bumped
  to 0.31 (0.28's generated Swift hit a duplicate-attribute error under Swift
  6.2; 0.31 is clean).
- `rust/cw-core/scripts/build-xcframework.sh` cross-compiles 4 Apple slices
  and assembles `CwFfi.xcframework` (ios-arm64, ios-arm64-simulator,
  macos-arm64_x86_64 universal — **staticlibs only**, since iOS apps can't
  ship arbitrary dylibs and vendored OpenSSL only resolves as `.a`).
- `CarrierWaveCore/Package.swift` gained a `CwFfi` binary target and a
  `CarrierWaveCwFfi` Swift target that holds the UniFFI-generated bindings.
  Artifacts stage into `swift/packages/CarrierWaveCore/{Vendored,Sources/CarrierWaveCwFfi}`
  (gitignored).
- `QueryAnalyzer.analyzeViaRust(_:qsoCount:)` / `validateViaRust(_:)` in
  `QueryAnalyzer+Rust.swift` forward to Rust and lift `FfiQueryAnalysis` back
  into the Swift `QueryAnalysis` shape. The Swift API surface stays
  unchanged; this is the shim pattern every later phase will reuse.
- `QueryAnalyzerRustParityTests` runs 11 vectors through both paths and
  asserts equal `usesIndex` / `estimatedCost` / `requiresConfirmation` /
  `shouldWarn`. Green on macOS today.

**Caveats still open:**
- The XCFramework script is local-only. The `Vendored/` artifact is
  gitignored; a fresh checkout must run the script before `swift build`.
- macOS deployment target on the OpenSSL slice mismatches `Package.swift`'s
  `.macOS(.v14)` (currently builds against the host SDK). Non-fatal linker
  warnings only; should be pinned via `MACOSX_DEPLOYMENT_TARGET=14.0` once
  CI is wired.
- The full Swift "replace" shim (have `QueryAnalyzer.analyze` itself
  delegate to Rust) is intentionally deferred — the parallel path proves
  parity first.

### 2. Set up the CI lane for cw-core — NEW HIGHEST LEVERAGE
- Add `cargo build/test/clippy -p` (workspace) as a GitHub Action; cache the
  SQLCipher/OpenSSL build.
- Add a `build-xcframework` job that runs the script and exports the result
  as an artifact (or a GitHub Release asset Xcode Cloud can fetch).
- Gate Xcode Cloud's `swift test --filter QueryAnalyzerRustParityTests`
  step on that artifact (proves parity on device/sim/macOS, not just the
  host).
- Gate merges on both lanes.
- (Infra/CI is still pending per root `CLAUDE.md` — coordinate with that.)

### 3. ✅ Finish the FT8 vertical (Phase 1) — DONE 2026-06-13
- `cw-ft8/build.rs` compiles vendored `ft8_lib` via the `cc` crate with the
  same `HAVE_STPCPY` define the Swift CFT8 target uses; `bindgen` over the
  same headers produces `ffi.rs` at build time.
- `decoder.rs` / `encoder.rs` / `wav.rs` are safe Rust wrappers mirroring
  `FT8Decoder.swift` / `FT8Encoder.swift` exactly (same OSR, same candidate
  cap, same dedup-by-text, continuous-phase 8-FSK).
- `tests/wav_parity.rs` decodes the same WAV fixtures Swift uses and asserts
  ≥ half of `kgoba/ft8_lib`'s expected text appears in the output — same
  threshold Swift gates on. Encoder round-trip test confirms
  `encode("CQ K1ABC FN42")` decodes back.

### 4. ✅ Grow cw-domain (Phase 2) — DONE 2026-06-13
All Swift-source domain modules are now mirrored on the Rust side
(215 cw-domain tests). The previously-deferred matchers and TOTA scoring
were ported with their own value-type inputs (`QsoSnapshot`,
`TotaScoringInputs`, `TilePathSample`, `T3SpotRecord`) so they don't
depend on `cw-store`/SwiftData — the iOS shim projects its model objects
into those structs before calling in.

**Reference data canonicalization is complete on the Rust side:**
the DXCC primary-prefix table (`location_prefix::COUNTRIES`, ~155 entries),
US FCC band plan (`band_plan::SEGMENTS` + per-region calling-frequency tables),
and Natural Earth coastlines (`data/coastline.json` → 103 polygons /
4,982 lat/lon pairs, loaded via `include_bytes!`) are the canonical sources;
the Swift side regenerates from here.

**Two small follow-ups stay open** (none block the FFI work):
- `BandPlan+Activities.swift` (CWT time windows, ARRL usage zones,
  `FrequencyActivity` table) — view-layer hint data, port when the Phase 4
  iOS shim needs it crossed over.
- The extended-prefix table (Swift's `DescriptionLookup.dxccEntities`
  mapping DXCC numbers → all known prefixes for that entity) — depends on a
  description-lookup port that isn't sequenced yet.

### 5. Build out the store (Phase 4) — then the hard part
- ✅ **All 13 `@Model` entities modelled in `cw-store`** (2026-06-14): QSO plus
  LoggingSession, ServicePresence, SessionSpot, ActivationMetadata, ActivityLog,
  EquipmentItem, RadioMacro, WebSDRRecording, WebSDRFavorite, UploadDestination,
  CloudSyncMetadata. Each is a value struct + `*_DDL` const + bounded
  upsert/count/fetch CRUD + round-trip tests, same shape as `qso.rs`. Schema v2
  in `migrations.rs`. Blobs stored verbatim as BLOB; relationships as FK columns.
  59 cw-store tests; workspace 339; clippy-clean.
- ✅ **All 13 entities exposed over `cw-ffi`** (2026-06-14): `cw-ffi/src/entities/`
  has one module per entity — `Ffi<Entity>` record + `From` both ways + a
  `#[uniffi::export] impl FieldStore` CRUD block (upsert/count/fetch-list/
  fetch-by-key). `FieldStore.inner` is now `pub(crate)`. UniFFI 0.31 accepts the
  multiple `impl FieldStore` blocks across modules. Swift + Kotlin bindings
  regenerate cleanly. Natural/composite keys + filter-less config tables handled.
- ✅ **Observation API prototyped** (2026-06-14): `cw-ffi/src/observation.rs` adds
  a foreign `StoreObserver` trait (`#[uniffi::export(with_foreign)]`),
  `FfiStoreTable`/`FfiChangeKind`/`FfiStoreChange`, and a token-keyed
  `ObserverRegistry` on `FieldStore` with `add_observer`/`remove_observer`. Every
  entity upsert drops the DB lock *then* calls `notify`, so an observer can
  re-enter the store from `on_change` without deadlock (3 tests, incl.
  `callback_can_reenter_store_without_deadlock`). Swift side:
  `FieldStore.changes(for:)` (`FieldStore+Observation.swift`) wraps it in an
  `AsyncStream<FfiStoreChange>` (buffering newest-1 so an upsert burst collapses
  into one refresh), auto-registering/removing over the stream's lifetime.
  **All 12 entities now emit upsert changes** (2026-06-14). **Remaining:** expose
  entity deletes so `notify` can emit `Delete`; add a Swift parity test
  exercising `changes(for:)` on device/sim.
- Write the **one-time SwiftData→SQLite importer** (GRDB experience de-risks it).
- **Then the bulk of the whole project:** decouple the 370+ files importing
  SwiftData, entity-by-entity behind a feature flag, read-only mirror first then
  cut writes. iOS + macOS in lockstep. Track as its own epic; this is months.

### 6. Network + sync + auth (Phases 3, 5)
- ✅ `cw-net` Phase 3 — model + parsing + reqwest transport for
  POTA/SOTA/WWFF/PSKReporter/DONKI/HamQSL/LoFi landed 2026-06-13 (38 tests,
  clippy-clean). PSK rate-limit and DONKI/HamQSL caches mirror the Swift
  actors. Credentials still live in the Swift keychain — the LoFi transport
  takes the bearer token as an argument. Remaining: wire the new clients
  behind UniFFI and delete the Swift `actor`s once parity tests light up
  from device builds.
- `cw-sync`: implement the HTTPS `SyncTransport` against new server `/sync`
  endpoints; build server-side sync tables + change feed in Postgres; define the
  `cw-sync-proto` shared crate. Dual-run against CloudKit, migrate, retire CK.
- **Auth overhaul gates Phase 5:** replace the static `fd_…` device token with
  OAuth2 access/refresh + rotation + revocation, one identity shared with the
  social API. Sort the three open questions below first.

---

## Open questions to resolve before the gated work

| Question | Blocks | Notes |
|---|---|---|
| Device-token → OAuth migration UX | Phase 5 auth | Silent upgrade vs. forced re-auth |
| Refresh-token storage + revocation-list design | Phase 5 server | Server-side |
| SQLCipher key recovery when keychain item is lost | Phase 4 ship | Device-restore flow |
| ~~Observation/`@Query` replacement shape~~ | ~~Phase 4 consumer migration~~ | ✅ Resolved 2026-06-14 — `StoreObserver` callback + `FieldStore.changes(for:)` `AsyncStream`; lock released before notify (reentrancy-safe) |

## Environment notes (why some steps aren't done yet)

The cloud container that produced the original plan had **no Xcode**, no
`uniffi-bindgen` on PATH, and no live network for app traffic. The Phase-0
loop has since been closed on a local Xcode machine (2026-06-13). The
FT8 C-link + decode validation, live network I/O, the sync server, and the
SwiftData decoupling remain documented seams.

## Conventions for whoever continues

- **Faithful ports only:** name the Swift source in a module doc comment; assert
  observable parity (capture Swift outputs into fixtures, diff against Rust).
- **FFI surface lives only in `cw-ffi`** — nothing else `pub` across the boundary.
- **Bounded queries at the store**, never "fetch all" — `MAX_FETCH_LIMIT` exists
  to enforce the perf rules at the data layer.
- Update `rust/cw-core/FILE_INDEX.md` when adding/moving files.
- Each phase stays independently shippable; you can stop after any one with a
  working app.

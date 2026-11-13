# Rust Core Migration — Cross-Platform Foundation

> **For current status + the single ordered next-steps list, see
> [rust-migration-status.md](rust-migration-status.md).** This doc is the original
> master design (phases 0–6); the status hub tracks where the work actually is.

**Status:** Draft / design
**Date:** 2026-06-13
**Scope (decided):** Full data layer into Rust — pure logic + FT8 DSP + network API clients + persistence + sync. UniFFI bindings, **Swift-first** consumer (apps keep working while Rust is swapped in behind today's APIs); Android/Kotlin bindings generated from the same core later.

**Decisions locked (see §10):** SQLCipher encrypted-at-rest store · single unified identity with a hardened **OAuth2-style access/refresh + rotation + revocation** auth · canonical reference data **moves into the Rust repo** · RemoteOp protobuf **schema lives in `cw-domain`** (Swift keeps transports) · macOS **Sweep migrates lockstep with iOS**.

---

## 1. Goal & non-goals

**Goal.** Extract Carrier Wave's domain logic, persistence, and sync out of the Apple-only Swift packages (`CarrierWaveCore`, `CarrierWaveData`) into a single portable **Rust core** (`cw-core`), consumed by Swift today via UniFFI and by Android/desktop later from the *same* compiled library. End state: **Swift/Kotlin own UI only; Rust owns logic, storage, and sync.**

**Non-goals (this plan).**
- No UI framework decision. This plan deliberately makes the core portable so the UI choice (Skip / Flutter / native Compose) is deferred and reversible.
- No rewrite of the iOS/macOS UI. We change *what views read from*, not how they render.
- No change to the social/activities server API surface (challenges, feed, leaderboard). Those stay as-is; we *add* a sync backend alongside them.

---

## 2. Current state (grounded)

| Fact | Value | Implication |
|---|---|---|
| `CarrierWaveCore` Swift | 137 files / ~28.7k LOC | Almost all `Foundation`-only (125/137 imports). Apple coupling is at the edges: 2 `SwiftUI` (share-card renderers), 1 `Accelerate`, 1 `Network`+Multipeer (RemoteOp), 1 `Security`, 1 `OSLog`. |
| FT8 DSP | `Sources/CFT8` = vendored `ft8_lib` (MIT, KISS FFT + LDPC) | **Already portable C.** Rust links it directly via FFI; no DSP rewrite. |
| `CarrierWaveData` Swift | 186 files / ~30.5k LOC | 13 `@Model` SwiftData entities. Already depends on **GRDB (SQLite)** + raw `SQLite` in places. |
| Sync | `CloudSyncJournalEngine` (journal + conflict resolver + snapshot service) over **CloudKit transport** (`CKContainer`/`CKModifyRecordsOperation`) | The hard part (journal, field extraction, conflict resolution) is already abstracted behind a delegate protocol. CloudKit is "just" the transport. |
| **Consumer coupling** | **370 files** import `SwiftData`; **341** use `@Query`/`ModelContext`/`FetchDescriptor`; **465** reference `QSO`/`LoggingSession`/`ServicePresence` directly | **This is the dominant cost of the whole effort — not the logic port.** |

### Honest cost assessment
Porting the logic and FT8 is the *easy, fun* part — weeks, mostly mechanical, with the C codec already done. The expensive, risky part is **prying 370+ files off SwiftData**. SwiftData `@Model` objects are reference types with change-tracking, lazy relationships, and `@Query` view integration baked deep into the view layer. Replacing that with a Rust-owned store means every `@Query`, every `modelContext.insert`, and every live-updating view has to move to an explicit fetch/observe API. That is the multi-quarter line item. Plan and staff accordingly; do **not** sequence it as "port logic, then flip a switch."

The hard performance constraints in `swift/CLAUDE.md` (QSO count must never affect main-thread responsiveness; max 1,000 objects loaded; batched fetches; serialized full-table scans) become **requirements on the Rust FFI API**, not just the Swift side. The FFI must expose bounded, paginated, off-main-thread queries — never "give me all QSOs."

---

## 3. Target architecture

```
┌─────────────────────────────────────────────────────────────┐
│  UI (per platform)                                           │
│  iOS/macOS SwiftUI today · Android Compose later             │
└───────────────▲─────────────────────────────────────────────┘
                │ UniFFI-generated bindings (Swift / Kotlin)
┌───────────────┴─────────────────────────────────────────────┐
│  cw-core  (Rust, single library)                             │
│                                                              │
│  cw-domain   parsers, codecs, math, matchers, scoring,       │
│              rig protocols, state machines (pure, no I/O)    │
│  cw-ft8      safe Rust wrapper over vendored ft8_lib (C)     │
│  cw-store    SQLite (rusqlite/SQLCipher) — entities, queries,│
│              migrations, bounded/paginated fetch API         │
│  cw-net      reqwest async API clients (SOTA/WWFF/PSK/…)     │
│  cw-sync     journal engine + conflict resolver +            │
│              server-sync client (replaces CloudKit transport)│
│  cw-ffi      UniFFI interface (udl/proc-macro), the only     │
│              crate that defines the cross-language surface    │
└───────────────▲─────────────────────────────────────────────┘
                │ HTTPS sync protocol (new)
┌───────────────┴─────────────────────────────────────────────┐
│  Rust server (existing)  + new /sync endpoints + Postgres    │
└─────────────────────────────────────────────────────────────┘
```

Workspace lives at `rust/cw-core/` (new top-level alongside `server/` and `swl/`), as a Cargo workspace of the crates above. `server/` may later share types with `cw-sync` via a small `cw-sync-proto` crate.

---

## 4. Crate breakdown & what moves where

| Swift today | → Rust crate | Notes |
|---|---|---|
| ADIF/CTY/Ham365/Polo/QuickEntry/RadioCommand parsers, QueryLanguage lexer+parser+AST+analyzer | `cw-domain::parse` | Mechanical port. `nom`/hand-rolled. QueryLanguage is self-contained — good first real port. |
| Callsign detection + edit distance, dedup, twofer, SCP database | `cw-domain::callsign` | Regex → Rust `regex` crate. |
| Maidenhead, azimuthal projection, band utilities, frequency formatter, unit formatter | `cw-domain::geo` / `::fmt` | Pure math. Property-test against Swift outputs. |
| TOTA scoring/detector/correlator/winter, streak calculator, mode equivalence, propagation estimator, antenna patterns | `cw-domain::scoring` / `::propagation` | Pure. |
| CI-V / Kenwood / Yaesu / text protocol parsers, BCD encoding | `cw-domain::rig` | Byte-level; exhaustively testable. |
| Morse tables + edit distance, NATO phonetics, phonetic interpreter, CW text elements | `cw-domain::cw` | Pure. |
| **Reference data**: CoastlineData (6 files), DXCC tables, LocationPrefix tables, BandPlan tables | `cw-domain` (canonical source **moves into the Rust repo**) | **Migrate as data, not code.** One-time conversion of the Swift tables to canonical TOML/JSON/CSV under `cw-domain/data/`; build step embeds via `include_bytes!`. Rust becomes the single source of truth; if Swift ever needs a copy, it's generated from here. |
| `Sources/CFT8` + FT8Decoder/Encoder/Message/Constants/StateMachine/EnrichedDecode/WaterfallData | `cw-ft8` | Wrap the C lib with `bindgen`/`cc`. Encoder/decoder logic is thin over C; message + state machine are pure Rust ports. Waterfall magnitude data exposed as a buffer over FFI. |
| SOTA/WWFF/PSKReporter/DONKI/HamQSL/Ham365/LoFi clients (Swift `actor`s, URLSession + XML/JSON) | `cw-net` | `reqwest` + `tokio`; XML via `quick-xml`. UniFFI async fns. Caching (15/30-min) moves to Rust. |
| 13 `@Model` entities + GRDB usage | `cw-store` | **SQLCipher** (encrypted-at-rest) schema + migrations owned by Rust; DB key held in the platform keychain, passed in over FFI. Entities become plain Rust structs + DTOs. |
| `CloudSyncJournalEngine` + conflict resolver + snapshot/journal entry/zone | `cw-sync` | Port the journal/field-extraction/conflict logic; replace CloudKit transport with HTTPS-to-server. |

**Stays in Swift (do not move):**
- `Sharing/LinkPreviewCardView` + `LinkPreviewCardRenderer` (SwiftUI `ImageRenderer`) — UI.
- `RemoteOp/NWConnectionTransport` + `MultipeerTransport` — platform networking; the *transports* stay in Swift, but the protobuf **frame schema + encode/decode move into `cw-domain`** (decided) so a non-Apple peer can speak RemoteOp later. Swift transports just move bytes.
- Keychain access (`Security`) — keep credential storage platform-native; Rust receives secrets via the FFI, never owns the keychain.

---

## 5. FFI strategy (UniFFI, Swift-first)

- **One FFI crate (`cw-ffi`)** owns the entire cross-language surface via UniFFI proc-macros. Nothing else is `pub` across the boundary. This keeps the binding surface auditable and stable.
- **Hide the object graph.** Do not expose live entities. Expose:
  - `record`/`enum` value DTOs (Codable-friendly, `Sendable` on the Swift side),
  - bounded query methods (`fetchQsos(filter, limit, offset) -> [QsoDto]`) — enforces the ≤1,000 / always-`fetchLimit` rules at the API level,
  - an **observation/callback interface** so SwiftUI can refresh on store changes (replaces `@Query` reactivity). UniFFI callback interface → Swift `AsyncStream`/`Observable` adapter. ✅ **Prototyped 2026-06-14** on the QSO path: `StoreObserver` foreign trait + `FieldStore.changes(for:) -> AsyncStream<FfiStoreChange>`; the store releases its DB lock before notifying, so observers can re-fetch from the callback without deadlock.
- **Async.** UniFFI async functions backed by a Rust `tokio` runtime owned by the core. Network + sync are async; store reads can be sync-and-fast or async-batched.
- **Errors.** One `CwError` enum mapped to a Swift `Error`. No panics across FFI — wrap with `catch_unwind` at the boundary.
- **Threading.** Core owns its runtime + a DB writer actor. FFI calls are thread-safe; the "no work on main thread" rule is satisfied by making store/network calls async off the Swift main actor.
- **Packaging.** Build an `XCFramework` (arm64 device + sim + macOS) consumed by the Swift packages as a binary target. Later: `.aar`/JNI for Android from the same crate.

A thin **Swift compatibility shim** keeps the *existing* `CarrierWaveCore`/`CarrierWaveData` public API signatures and forwards to the generated bindings. This is what lets us migrate behind today's APIs without touching 465 call sites on day one.

---

## 6. Phased migration

Each phase has an **exit criterion** and is independently shippable. No phase removes Swift code until its Rust replacement is at parity and validated against the existing test suite.

### Phase 0 — Toolchain beachhead (validate the bet)
- Stand up `rust/cw-core/` workspace, `cw-ffi` with UniFFI, XCFramework build, SPM binary target wiring, CI lane.
- Port **QueryLanguage** (self-contained, well-tested, zero I/O) end-to-end as the proof: Rust impl → UniFFI → consumed by a Swift test that runs the *existing* QueryLanguage test vectors.
- **Exit:** existing `CarrierWaveCoreTests` query cases pass against the Rust impl through FFI on device + sim + macOS in CI.

### Phase 1 — FT8 core ✅ DONE 2026-06-13 (Rust side)
- `cw-ft8` wraps vendored `ft8_lib`; port message types, constants, encoder/decoder wrapper, QSO state machine, enriched decode.
- Validate against `Tests/.../ft8-samples` WAV fixtures — bit-exact decode parity is the gate.
- **Exit:** all `FT8*Tests` pass through Rust; Swift FT8 codec deleted behind the shim.
- **Status:** decoder, encoder, WAV loader, FFI bindings, and the `wav_parity` integration test against the same `ft8_lib` fixtures Swift uses all green. Deleting the Swift codec is gated on the cw-ffi rewire (Phase 4 consumer pattern) per the handoff convention.

### Phase 2 — Pure domain logic ✅ DONE 2026-06-13 (Rust side)
- Port parsers, matchers, geo/math, rig protocols, scoring, CW/morse, propagation, reference-data generation.
- Strategy: **golden-output parity tests** — capture current Swift outputs for a corpus, assert Rust matches.
- **Exit:** `CarrierWaveCore` is a thin Swift shim over `cw-domain`; pure-logic Swift removed.
- **Status:** every Swift module identified for the domain layer is mirrored (query, band, mode, service-type, Maidenhead, formatters, antenna pattern + description parser, azimuthal projection, TOTA scoring + T3 correlator + tile detector + winter detector, QSO dedup + two-fer matchers, park-reference helpers, streak calculator, NATO phonetics, CW text elements, US band plan, IARU region). Reference-data canonicalization done: DXCC primary-prefix table, US FCC band segments + per-region calling frequencies, and Natural Earth coastlines (`data/coastline.json` → 103 polygons / 4,982 lat/lon pairs, loaded via `include_bytes!`). 215 cw-domain tests; clippy-clean. Swift-side shim deletion gated on the cw-ffi rewire (see Phase 4).
- **Remaining as small follow-ups** (don't block Phase 4): `BandPlan+Activities.swift` (CWT windows, ARRL usage zones, `FrequencyActivity` table) and the extended-prefix DXCC table behind `DescriptionLookup.dxccEntities`.

### Phase 3 — Network clients ✅ DONE 2026-06-13 (Rust side)
- Port API actors to `cw-net` (reqwest + quick-xml), including rate-limit/cache behavior.
- **Exit:** spot/space-weather/LoFi fetch paths run through Rust; Swift clients removed. Keep credentials in Swift keychain, passed in.
- **Status:** POTA/SOTA/WWFF/PSKReporter/DONKI/HamQSL/LoFi models + parsers + async reqwest/tokio transports landed; PSK rate-limit and DONKI/HamQSL TTL caches mirror the Swift actors. Credentials stay in the Swift keychain — the LoFi transport takes the bearer as an argument. 38 cw-net tests; clippy-clean. Swift-side client deletion gated on the cw-ffi rewire (Phase 4 consumer pattern).

### Phase 4 — Persistence (the big one)
- ✅ **Schema + all 13 entities modelled in `cw-store`** (2026-06-14): QSO +
  LoggingSession, ServicePresence, SessionSpot, ActivationMetadata, ActivityLog,
  EquipmentItem, RadioMacro, WebSDRRecording, WebSDRFavorite, UploadDestination,
  CloudSyncMetadata. Each = value struct + `*_DDL` const + bounded
  upsert/count/fetch CRUD + tests, mirroring `qso.rs`. Schema v2 migration; DB
  key passed in at open. 59 cw-store tests.
- ✅ **All 13 entities exposed over `cw-ffi`** (2026-06-14): each has an
  `Ffi<Entity>` record + `From` conversions + `FieldStore` CRUD (upsert/count/
  fetch-list/fetch-by-key) in `cw-ffi/src/entities/`. Swift + Kotlin bindings
  regenerate cleanly; clippy-clean.
- ✅ **Observation API prototyped** (2026-06-14): `StoreObserver` callback + `FieldStore.changes(for:)` `AsyncStream` adapter, reentrancy-safe (lock released before notify; Rust re-entry test green). All 12 store entities fire `notify(...)` from their upsert.
- ✅ **Entity deletes exposed for ALL 12 entities** (2026-06-17): `delete_*` in `cw-store` + `cw-ffi`, each firing `notify(.Delete)` (id-keyed for most; natural-key for activation_metadata/websdr_favorite/cloud_sync_metadata). xcframework regenerated; iOS links. Unblocks `CwStoreMirror` covering non-QSO deletes.
- ✅ **QSO consumer cutover (reads A/B/C + writes W0–W3)** complete behind the off-by-default `cwStoreQSOMode` experiment: Logbook reads + count from cw-store in `on`; all interactive/bulk/restore/import QSO writes are cw-store-first.
- ⏳ **Remaining:** the **one-time SwiftData→SQLite importer** for the non-QSO entities (existing GRDB usage de-risks this) + a Swift end-to-end parity test; extend `CwStoreMirror` to observe all entities; then the entity-by-entity consumer cutover (reads + writes), and finally deleting SwiftData.
- Migrate **iOS (Field) and macOS (Sweep) in lockstep** — both share `CarrierWaveData`, so the shim covers both and we never run two storage backends bridged locally. Go **incrementally, entity by entity**, behind a feature flag: start read-only mirrors, then cut writes over. Replace `@Query` with fetch-on-`.task` + observation callbacks (note: the perf rules already pushed `@Query` out of QSO/ServicePresence, so the hottest paths are partly pre-adapted).
- **Exit:** SwiftData removed from both apps; `import SwiftData` count → 0; apps run on the encrypted Rust store with the existing performance tests green.

### Phase 5 — Sync (CloudKit → server) + auth hardening
- Port `CloudSyncJournalEngine` logic to `cw-sync`; implement HTTPS transport to **new server `/sync` endpoints** (journaled changes, conflict resolution, snapshot upload). Reuse the existing conflict-resolution semantics.
- **Auth overhaul (gates this phase):** replace today's static opaque device token (`server/src/auth/token.rs`) with a **single unified identity** behind an **OAuth2-style scheme — short-lived access tokens + refresh tokens, server-side rotation and revocation, scopes**. Same identity powers the existing social API; sync calls carry scoped access tokens. Plan a migration path for existing device tokens.
- Add server-side: sync tables in Postgres, per-account zones, change feed, token/refresh storage + revocation list. Define `cw-sync-proto` shared crate.
- **Dual-run** against CloudKit during validation; migrate accounts; then retire CloudKit.
- **Exit:** cross-platform sync works against the Rust server over the hardened auth; CloudKit transport removed. **This is the deliverable that unlocks Android** (per the original "can't use CK" requirement).

### Phase 6 — Second consumer (proves portability)
- Generate Kotlin bindings from the unchanged core; stand up a minimal Android target reading the same store + sync. Validates that nothing Apple-specific leaked across the FFI.
- ✅ **Spiked early (2026-06-14):** `android/` Jetpack Compose "mini logbook"
  consumes the unchanged `cw-ffi` via UniFFI **Kotlin** bindings + cargo-ndk;
  the encrypted SQLCipher `FieldStore`, query analyzer, and maidenhead functions
  all run on an arm64 emulator (write→count→read-back→on-device db verified). The
  `.so`/bindings build dynamically via `android/build-rust.sh` (gitignored
  output). Proves portability ahead of schedule; full parity awaits the Phase 4
  FFI rewire + Phase 5 sync.

---

## 7. Testing & parity

- **Parity-first.** For every ported unit, the gate is "produces identical output to the Swift original" against the existing test corpus — not "tests pass in isolation." Build a small harness that runs Swift and Rust over the same inputs and diffs.
- Reuse existing fixtures (FT8 WAVs, ADIF samples, Ham365 HTML, query vectors).
- Rust-side: `cargo test` + `proptest` for math/parsers; `criterion` benchmarks for FT8 decode and store queries (guard the perf rules).
- Keep the Swift test suites running against the shim throughout — they become the cross-language integration tests.

## 8. Build & CI

- New CI lane: `cargo build/test/clippy` for `cw-core`, then XCFramework build, then the Swift suites against it. Add to the existing Xcode Cloud merge gate.
- `swl/` and `server/` already establish Rust-in-monorepo conventions — reuse their `Cargo.toml`/CI patterns and lints.
- Update `FILE_INDEX.md` files and add `rust/cw-core/FILE_INDEX.md` as crates land.

## 9. Risks & mitigations

| Risk | Mitigation |
|---|---|
| **Consumer decoupling (370+ files) dwarfs the logic port** | Phase 4 is staffed and scheduled as the main effort; entity-by-entity behind flags; shim keeps APIs stable so it isn't a big-bang. |
| `@Query` reactivity has no 1:1 Rust equivalent | Observation callback interface + Swift `Observable`/`AsyncStream` adapter. ✅ Prototyped 2026-06-14 (`StoreObserver` + `FieldStore.changes(for:)`); reentrancy-safe (lock released before notify). |
| FFI overhead on hot paths (waterfall, large fetches) | Expose buffers/batches, not per-item calls; benchmark in Phase 1/4; keep zero-copy where possible. |
| Sync regression / data loss during CloudKit→server cutover | Dual-run, read-only mirror first, reversible flag, backups (see `2026-02-20-db-backup-strategy.md`). |
| UniFFI async + tokio runtime lifecycle bugs | Single owned runtime in core; integration-test cancellation/teardown early. |
| Scope creep into a stalled multi-quarter rewrite | Every phase independently shippable; can stop after any phase with a working app. Phases 1–3 deliver value even if 4–5 slip. |

## 10. Decision log

All scoping questions resolved 2026-06-13:

| # | Question | Decision |
|---|---|---|
| — | Scope of the Rust core | **Full data layer** — logic + FT8 + network clients + persistence + sync |
| — | Binding strategy / first consumer | **UniFFI, Swift-first** (Android later from same core) |
| 1 | At-rest encryption | **SQLCipher** — encrypted local store; DB key in platform keychain, passed over FFI |
| 2 | Sync identity | **Single unified identity** (shared with social API), but auth posture **dramatically hardened** |
| 2a | Auth mechanism | **OAuth2-style** — short-lived access + refresh tokens, rotation, server-side revocation, scopes (replaces today's static `fd_…` device token) |
| 3 | Reference data (DXCC/CTY/BandPlan/coastline) | **Move canonical source into the Rust repo** (`cw-domain/data/`); generate any Swift copy from there |
| 4 | RemoteOp protobuf frames | **Schema + serialization move to `cw-domain`**; Apple transports (NWConnection/Multipeer) stay in Swift |
| 5 | macOS Sweep timing | **Lockstep with iOS** through Phases 4–5 |

### Still to settle (downstream design detail, not blocking the phasing)
- Existing-device-token → OAuth migration UX (silent upgrade vs. forced re-auth).
- Refresh-token storage/rotation specifics + revocation-list design on the server.
- SQLCipher key rotation / recovery flow when keychain item is lost (device restore).

---

## 11. Implementation status (updated 2026-06-14)

A working `rust/cw-core/` Cargo workspace now exists with **339 passing tests**
(`cargo test --workspace`) and a clean `cargo clippy`. This is a real,
compiling, tested foundation across every phase's logic — not scaffolding.
Since the original 2026-06-13 writeup: Phases 1–3 closed on the Rust side, the
Phase-0 Swift binding loop closed on a local Xcode machine, all 13 cw-store
entities are modelled (Phase 4 groundwork), and the Android second consumer was
spiked (Phase 6). What's done vs. what remains:

| Crate | Phase | Built & tested | Remaining (and why) |
|-------|-------|----------------|---------------------|
| `cw-domain` | 0, 2 | Full query language + band/mode/service-type/Maidenhead + formatters + antenna patterns + azimuthal projection + TOTA scoring/detectors + dedup/two-fer matchers + park-reference helpers + streak calculator + NATO phonetics + CW text elements + US band plan + IARU region + DXCC primary-prefix table + embedded Natural Earth coastlines (`data/coastline.json`). **Phase 2 closed on the Rust side; 215 tests.** | Plug remaining Swift call sites into the UniFFI shim (Phase 4 consumer work) and let the extended DXCC prefix table follow from the description-lookup port whenever it lands. |
| `cw-ft8` | 1 | `Ft8Constants` + `Ft8Message` logic (6 tests) | C decoder binding over the already-vendored `ft8_lib` (`cc`/`bindgen`), gated on the WAV-fixture parity harness |
| `cw-store` | 4 | **Real SQLCipher** encrypted store: schema/migrations, bounded query API, wrong-key-fails test, **all 13 entities modelled** with bounded CRUD (59 tests) | SwiftData→SQLite importer; **consumer decoupling of 370+ Apple files (the bulk of the work)** |
| `cw-net` | 3 | **Phase 3 done**: SOTA/WWFF/PSK/DONKI/HamQSL/LoFi models + parsers + reqwest/tokio transport with rate-limit (PSK) + TTL cache (DONKI 30 min, HamQSL 15 min). 38 tests. | Wire the transports behind the UniFFI shim (`cw-ffi`) and retire the Swift `actor`s when device parity tests light up. |
| `cw-sync` | 5 | Journal types + conflict resolution (field-level merge, notes-merge, LWW) + transport trait + in-memory transport (7 tests) | HTTPS server transport; server-side `/sync` endpoints + Postgres; OAuth2 auth overhaul |
| `cw-ffi` | 0 | UniFFI surface: query + maidenhead + `FieldStore` with **all 13 entities' CRUD** (`entities/*.rs`) + the **`StoreObserver` change-callback** (`observation.rs`); **Swift XCFramework** (consumed by `CarrierWaveCore`) and **Kotlin** (consumed by `android/`) bindings regenerate cleanly; **delete FFI for all 12 entities** (`notify(.Delete)`, 2026-06-17) | Expose the `cw-net`/`cw-sync` paths; the Swift compatibility shim that cuts call sites over |

**Since closed on a local toolchain (2026-06-14):**
- ✅ UniFFI binding generation — Swift XCFramework (Xcode) **and** Kotlin
  (cargo-ndk, Android) both generate from the unchanged `cw-ffi`.
- ✅ FT8 C-decoder link + WAV-fixture parity (Phase 1 closed).
- ✅ Live network parsing/transport (`cw-net`, Phase 3).

**Still remaining (the real bulk of the work):**
- Live sync server deployment + the OAuth2 auth overhaul (Phase 5).
- Replacing SwiftData across 370+ Apple-side files — the acknowledged bulk of
  Phase 4. Its two prerequisites are now in place: the `cw-ffi` entity rewire and
  the observation API (prototyped 2026-06-14).

**Phase 0 beachhead is proven in Rust:** the QueryLanguage port passes a parity
test suite end-to-end, validating the lexer→parser→AST→analyzer loop and the
UniFFI surface it's exposed through. The toolchain bet holds.

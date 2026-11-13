# Finishing the Rust-ification — Handoff

**Date:** 2026-06-18
**Branch:** `main`
**Scope:** the "pick it up from here" doc for completing the SwiftData → Rust `cw-store`/`cw-sync` migration (Phases 4–6 of [the migration plan](2026-06-13-rust-core-migration.md)).
**Companion docs:**
[migration plan](2026-06-13-rust-core-migration.md) ·
[QSO cutover decomposition](2026-06-14-qso-rust-store-cutover-design.md) ·
[QSO write-cutover handoff (W0–W3)](2026-06-17-qso-write-cutover-handoff.md) ·
[cw-store fidelity audit](2026-06-14-cw-store-fidelity-audit.md)

---

## TL;DR — where we are

The Rust core (`rust/cw-core/`: `cw-domain`, `cw-ft8`, `cw-store`, `cw-net`, `cw-sync`, `cw-ffi`) is **built and tested** on the Rust side for every phase's logic. The **logic port (Phases 1–3) is done**; the remaining work is the expensive part the plan always called out: **prying SwiftData out of the app (Phase 4)** and **replacing CloudKit with a server sync + OAuth2 auth (Phase 5)**, then proving portability with Android (Phase 6).

**QSO is the only entity fully cut over** (reads + writes) and only behind the hidden, off-by-default `cwStoreQSOMode` experiment (`off`/`shadow`/`on`). Everything else still reads/writes SwiftData; `CwStoreMirror` now keeps the *entire* cw-store in sync in `shadow`/`on` but nothing reads the non-QSO tables from cw-store yet.

**Nothing is live for users.** The flag is off by default and has **not** passed on-device smoke. In production terms the app is still 100% SwiftData.

## What's done (verified)

- **Phases 0–3 (Rust side):** toolchain/UniFFI, FT8 codec (WAV parity), pure domain logic (215+ tests), network clients. Swift-side deletion of the ported code is gated on the per-area cutover.
- **QSO reads (A/B/C):** Logbook list + count served from cw-store in `on`; `.cwquery` DSL compiled to SQL at parity (68-query corpus). `QSORowSnapshot` + `LogbookSnapshotSource`.
- **QSO writes (W0–W3):** every interactive/bulk/restore/import QSO write is cw-store-first in `on` via `QSOWriteSink`; SwiftData kept as the CloudKit adapter. See the [W0–W3 handoff](2026-06-17-qso-write-cutover-handoff.md).
- **Entity delete FFI (2026-06-17):** all 12 entities have `delete_*` in `cw-store` + `cw-ffi` (id-keyed + 3 natural-key), each firing `notify(.Delete)`. 86 cw-store tests; clippy clean; xcframework regenerated.
- **CwStoreMirror covers all 12 entities (2026-06-18):** `shadow`/inbound saves dual-write every entity (upserts + deletes) to cw-store. Compiles clean; existing mirror/seam suite unaffected. (Runtime test of the new entity path is pending — see Known issues.)

## What remains — ordered

### Phase 4 — finish prying out SwiftData (the bulk)

The per-entity pattern (proven on QSO) is: **mirror coverage → read cutover → write seam → parity**. Mirror coverage now exists for all entities, so each remaining entity needs *reads + writes*.

1. **Per-entity read cutover.** QSO got a full `.cwquery` → SQL compiler + snapshot source (slices B/C). Most other entities are read via plain `@Query`/`FetchDescriptor`, so they need a `*ReadSource`/snapshot seam routed by the mode flag, backed by the existing bounded `fetch_*`/`*_count` FFI. Sequence by coupling:
   - **ServicePresence** — already live-mirrored + read-projected onto QSO rows (slice B). Closest to done; needs standalone write authority for the non-QSO-adjacent mutations (sync-upload marking via `markPresent`/`markUploaded`).
   - **LoggingSession** — most central; read in many views. Largest read-cutover surface after QSO.
   - **SessionSpot, ActivityLog, ActivationMetadata, EquipmentItem, RadioMacro, WebSDRRecording/Favorite, UploadDestination, CloudSyncMetadata** — smaller, more peripheral.
2. **Per-entity write seam.** Generalize the `QSOWriteSink` pattern (cw-store-first in `on`, mirror-suppressed SwiftData save) per entity, routing each entity's write sites. Reuse the `CwStoreMirror.beginSeamWrite/endSeamWrite` echo-suppression already in place.
3. **Non-list / aggregation reads.** Stats, map snapshots, DXCC/WAS rollups, complex `#Predicate` fetches still hit SwiftData. These need new Rust query/analytics surface in `cw-store` (extend the query crate) before they can move. Bigger than list reads.
4. **Consumer-snapshot unwind.** `logQSO` (and the equivalent for other entities) still returns/holds live `@Model` objects; `QSOLedger`, widget, Live Activity, `processActivityForQSO`, `.didLogQSO` consumers ride those. Migrate them onto `QSORowSnapshot`/the id-bridge. **Riskiest refactor** (contact-logging hot path + upload-triggering activity detection) — sequence it *with* the SwiftData removal, not before.
5. **One-time importer for non-QSO entities + actually delete SwiftData.** The seed importer (`SwiftDataStoreImporter`) projects all 13 entities; wire the one-time SwiftData→SQLite import for the non-QSO ones, add a Swift end-to-end parity test, then drive `import SwiftData` → 0 (370 files / 341 `@Query`-`ModelContext` sites / 465 entity references). **Exit criterion for Phase 4.**
6. **macOS Sweep in lockstep.** Same `CarrierWaveData` shim covers both apps; apply the same seams to Sweep so we never run two storage backends bridged locally.

### Phase 5 — sync (CloudKit → server) + auth (entirely ahead)

`cw-sync` has journal types + conflict resolution + an in-memory transport only. Needed:
- HTTPS transport to **new server `/sync` endpoints** + Postgres sync tables, per-account zones, change feed; define `cw-sync-proto`.
- **OAuth2 auth overhaul (gates the phase):** replace the static `fd_…` device token with short-lived access + refresh tokens, rotation, server-side revocation, scopes; migration path for existing device tokens.
- **Dual-run against CloudKit**, migrate accounts, retire CloudKit. Once writes no longer need a SwiftData replica for sync, the `QSOWriteSink` SwiftData save + the id-bridge collapse away. **This is what unlocks Android.**

### Phase 6 — Android

Spiked already (`android/` Compose app consumes `cw-ffi` via Kotlin/cargo-ndk). Full parity awaits Phases 4–5. Note: the entity delete FFI (2026-06-17) flows to Kotlin only when `android/build-rust.sh` regenerates the bindings.

## How to add the next entity (concrete recipe)

1. **Mirror:** already done for all entities in `CwStoreMirror` (capture + `applyEntityWrites`). Verify the entity's `project(_:)` is `nonisolated public`.
2. **Read seam:** add `<Entity>ReadSource` (SwiftData + Rust impls + routing by `CwStoreQSOMode.current`), backed by `FieldStore.fetch_<entity>(s)`/`<entity>_count`. Add a `QSOParityProbe`-style parity check.
3. **Write seam:** add `<Entity>WriteSink` mirroring `QSOWriteSink` (cw-store-first + mirror-suppressed save in `on`); route the entity's write sites with the `commit*`/rollback/`CwStoreWriteLog` shape.
4. **Tests:** in-memory `Schema([<Entity>.self])` (NOT the full schema — see Known issues), mirror-roundtrip + read parity + write-authority.
5. **Docs:** changelog entry; update [migration plan](2026-06-13-rust-core-migration.md) status.

## Known issues / risks

- **Local test runners are both broken in this environment.** The **device** runner fails the whole `ImportServiceTests` class (and others) with `SwiftDataError.loadIssueModelContainer` + "Lost pending connection to the test runner." The **simulator** runner intermittently refuses to launch the host app (`RequestDenied` from SBMainWorkspace) — the app launches fine via `simctl` standalone. A `killall com.apple.CoreSimulator.CoreSimulatorService` + fresh sim *sometimes* yields a clean run. **Get a deterministic test run on a stable machine / CI.**
- **Full `CarrierWaveSchema` won't load in-memory here.** In-memory `ModelContainer(for: Schema(CarrierWaveSchema.models))` throws `loadIssueModelContainer` on this env. Tests must use a **minimal per-test schema** (e.g. `Schema([LoggingSession.self])`). The existing passing tests all do this.
- **`CwFfi.xcframework` is gitignored.** `rust/cw-core/scripts/build-xcframework.sh` must run on fresh checkouts / CI before the Swift side builds, and after ANY `cw-ffi`/`cw-store` change (it regenerates `CwFfi+Generated.swift` too). Builds device+sim+macOS slices.
- **Rust: no `cargo fmt`.** `rust/cw-core` is hand-formatted; the gate is `cargo build` + `cargo clippy -- -D warnings` + `cargo test`.
- **Mid-batch divergence on a cw-store write failure** (disk-full/corruption class): callers `rollback()` SwiftData + log to `CwStoreWriteLog`; rare, off-by-default, caught by the parity sweep.
- **`WebSDRFavorite` name collision:** the app target has its own `WebSDRFavorite`; use `CarrierWaveData.WebSDRFavorite` when referencing the `@Model`.

## Immediate next step (recommended)

Get a **deterministic test run** (CI or stable Mac) to confirm `testMirrorsLoggingSessionUpsertAndDelete` is green, then start the **ServicePresence** standalone write seam + **LoggingSession** read cutover — the two highest-value non-QSO entities — following the recipe above. Defer the consumer-snapshot unwind and non-list/aggregation reads until a few entities are cut over and the pattern is mechanical.

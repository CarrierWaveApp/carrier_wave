# Phase 4 SwiftData → cw-store cutover — status & remaining plan

**Date:** 2026-06-20
**Branch:** `rust/equipment-item-read-cutover` (merging to `main`)
**Companions:**
[migration plan](2026-06-13-rust-core-migration.md) ·
[finish handoff](2026-06-18-rustification-finish-handoff.md) ·
[LoggingSession write unwind spec](2026-06-20-loggingsession-write-unwind.md)

Everything below is behind the hidden, off-by-default `cwStoreQSOMode` experiment
(`off`/`shadow`/`on`). Nothing is live for users.

---

## The per-entity cutover, as it actually decomposes

For each entity: **mirror coverage → read seam → write seam → parity**. Mirror
coverage exists for all 12 entities. The work since is read seams (done) and write
seams (partial).

## Done (this branch)

### Reads — every entity, full field+order parity
Package-level `*ReadSource` (SwiftData impl + Rust `FieldStore` impl) returning
`count()` + an ordered `all() -> [*Snapshot]`, both backends projecting via the
canonical `SwiftDataStoreImporter.project(_:)`:

- QSO, EquipmentItem, **LoggingSession** (full 75-col), ServicePresence (count),
  ActivationMetadata, ActivityLog, CloudSyncMetadata, RadioMacro, SessionSpot,
  UploadDestination, WebSDRFavorite, WebSDRRecording.
- Ordering: `id`, else the natural key (`recordName`, `hostPort`, composite
  `(parkReference, date)`).
- Verified: `swift test` on `CarrierWaveData` — 29 RustStore tests green, sub-second.
  No Rust/xcframework change needed (the bounded `fetch_*` FFI already existed).

### Writes — generic seam + 3 entities routed
- `EntityWriteSink<Model>` (generic, `RustCountReadSource` factory idiom) mirroring
  `QSOWriteSink`: `on` writes cw-store first then a mirror-suppressed save;
  `shadow`/`off` unchanged. `EntityWriteSinkFactory` wires `upsert_*`/`delete_*` for
  all 11 uniform entities; type-keyed `EntityWriteSinkRegistry` routes
  `commitUpsert`/`commitDelete`. Registered/cleared with the QSO sinks in
  `applyQSOMirrorMode`.
- Routed (every user-CRUD site): **EquipmentItem**, **ActivityLog** (co-mutated logs
  batched), **RadioMacro** (tombstone = upsert).
- Verified: full iOS app target builds (`CarrierWave` scheme, arm64 simulator).

## Remaining — ordered

1. **LoggingSession write cutover** — **mechanism + lifecycle saves done; QSO-co-mutating
   and off-main saves deferred.** Built `SeamWriteBatch` (coordinated multi-entity seam:
   all co-mutated entities to cw-store under one suppression window, one save; ops resolve
   via `EntityWriteSinkRegistry`, registered in `applyQSOMirrorMode`). Routed:
   - **Multi-entity deletes** via `SeamWriteBatch` — `deleteCurrentSession` /
     `deleteSession` (session delete + SessionSpot deletes + hidden-QSO upserts).
   - **Single-entity session saves** via the existing `EntityWriteSink<LoggingSession>` —
     `pauseSession`, both `resumeSession`, `pauseOtherSession`, non-active `finishSession`,
     `activateSession` (create path), `nextRoveStop`, `observeGridChanges`.
   - **QSO-co-mutating session saves** (the QSO write cutover W0–W3 already shipped, so
     these were unblocked): `splitPOTAAtUTCMidnight` now returns a `SessionSplitChanges`
     (new sessions + reassigned QSOs + reassigned recordings) and `endSession` commits it
     via `SeamWriteBatch` (`commitSessionSplit`); `UTCDayBoundary.handleUTCDayRollover`
     routes its old+new session rollover through the same helper.
   - Verified: `xc build` green (device toolchain).
   **Update 2026-06-21 — remainder DONE.** `mergeSessions` routes its three shared saves
   via `SeamWriteBatch` (QSO reassignment; SessionSpot+WebSDRRecording reassignment + target
   mutation; shell delete), `deleteSessionShell` → `EntityWriteSink.commitDelete`, and the
   `+Continuity` inserts (`applyLANSnapshot`/`adopt`) → `EntityWriteSink.commitUpsert`. Full spec:
   [2026-06-20-loggingsession-write-unwind.md](2026-06-20-loggingsession-write-unwind.md).
2. **Off-main entity writes** — ✅ **DONE (2026-06-21).** The `@MainActor` design blocker is
   resolved by **per-context** mirror suppression (`CwStoreMirror.seamWriteDepth` keyed by
   `ObjectIdentifier(ModelContext)`, so a background seam save suppresses only its own save,
   not a concurrent main-context one) + a `nonisolated` `OffMainStoreSeam` (off-main analogue
   of `SeamWriteBatch`; `FieldStore`'s Rust `Mutex` makes concurrent store writes safe) + a
   `BatchedRewrite` `commit:` hook. Routed: SessionSpot `recordSpots`, WebSDRRecording
   create/finalize, ActivationMetadata (Conditions/WPM/LoFi-import), `POTAPresenceRepairService`,
   `WPMBackfillService`, `HuntingParkRefRepairService`, and `QSOProcessingActor`'s three
   presence-co-mutating saves (merge loop, `reconcileQRZPresence`, dead-state repair). Builds +
   deploys. **Left mirror-followed (safe):** SyncService upload-marking + the QSO-structural
   `QSOProcessingActor` repair fleet (Orphan/POTAGap/DataRepairs/SessionGrouping/POTAReconcile/
   applyQRZConfirmations) — Phase-5/QSO-cutover scope, not named non-QSO sites. **Gate:** the
   on-device shadow-parity sweep.
3. **CloudSyncMetadata** — **no actionable write site (2026-06-20).** A sweep finds
   **zero** `CloudSyncMetadata(...)` constructor calls and no `CloudSyncJournalEngine`
   reference to the `@Model` — it is migration/vestigial-only (the importer projects it;
   the mirror covers it). Nothing to route until/unless the sync engine starts writing it.
   Revisit if a live writer appears; otherwise close as N/A.
4. ~~**WebSDRFavorite type collision (blocker)**~~ — **RESOLVED 2026-06-20.** The
   app target's duplicate `@Model WebSDRFavorite` was registered in no schema (only
   `CarrierWaveData.WebSDRFavorite` is in `CarrierWaveSchema.models` / the live
   container), so the bare type the favorites UI used was never the persisted one.
   Deleted `swift/ios/CarrierWave/Models/WebSDRFavorite.swift`; the UI now resolves
   `WebSDRFavorite` to the package `@Model` (the schema-registered, persisted type) —
   both classes were byte-identical except access level. Favorite cutover unblocked.
5. **Consumer-snapshot unwind proper** — `logQSO` and friends still hand out live
   `@Model`s; `QSOLedger`, widget, Live Activity, activity detection ride those.
   Riskiest refactor; sequence with the SwiftData removal.
6. **Non-list / aggregation reads** — stats, map snapshots, DXCC/WAS rollups, complex
   `#Predicate` fetches still hit SwiftData; need a new Rust analytics surface.
   **Design scoped 2026-06-20:** [rust analytics surface design](2026-06-20-rust-analytics-surface-design.md)
   — SQL-`GROUP BY` aggregate catalog in cw-store reusing the `.cwquery` `WHERE` compiler
   + `cw-domain` grouping keys; `AnalyticsReadSource` protocol (SwiftData + Rust impls)
   parity-tested in the **package loop (no device)**.
   **Read sources COMPLETE 2026-06-21:** all aggregates implemented end-to-end (N0–N6 +
   MyParks per-park rollup + N5 state/entity follow-ons) — distinct counts, count-by,
   activation/park/equipment/combo rollups, grid tiles, WAS, DXCC-worked, state counts,
   service-presence counts, brag period metrics (SQL-trivial first cut; distance/streak/
   window metrics deferred to SwiftData by design). 19 cw-store + 12 Swift parity tests
   green; clippy + swiftlint clean.
   **Update 2026-06-21 — comprehensiveness audit + routing largely done:** the
   [analytics-models audit](2026-06-21-analytics-models-comprehensiveness-audit.md) added
   `pota_awards` (full POTAAwards port), `was250`, and `was_drilldown` aggregates beyond
   N0–N6, plus the **`pota_park` reference table (schema v4)** + `cw_domain::us_grid_state`
   port and an iOS POTAParksCache write-through. Consumer **routing is now largely
   complete**: StatsComputationActor (counts + `wasData`), GridOverlayDataActor,
   MyParksView, EquipmentStatsActor, AsyncServicePresenceCounts, and **POTAAwardsActor**
   overlay cw-store under `.on`. **Only `BragSheetComputationActor` remains unrouted** (its
   deep distance/streak/geographic stats are the next analytics slice — a scope reversal of
   the "deferred to SwiftData" call, now planned for Rust). cw-store 130 + cw-ffi 11 +
   cw-domain 223 tests green; Swift parity green; iOS app builds clean. Dormant until `.on`
   on-device. **Next steps + single continuation point:** [rust-migration-status.md](rust-migration-status.md).
7. **Importer trigger + delete SwiftData** — **trigger + e2e test DONE (2026-06-21).**
   The one-time in-app trigger was already wired (`CwStoreImportCoordinator.runIfNeeded`,
   idempotent via the `cwStoreImportCompletedVersion` marker; fires automatically on
   `.off → .shadow/.on` in `applyQSOMirrorMode` + manually via `CwStoreMigrationRow`). The
   end-to-end parity test landed: `EndToEndImportParityTests` seeds a multi-entity SwiftData
   graph, runs the real `importAll` batched path, and asserts read-source-seam parity (the
   per-entity read-source tests seed via per-row `project()`, never through `importAll`).
   Remaining for the exit criterion is the **on-device validation loop** (run the seed +
   routed reads on `theseus`), then drive `import SwiftData` → 0. **Caveat (2026-06-20):** the literal "delete
   SwiftData" half collides with SwiftData still being the **CloudKit bridge** — the QSO
   handoff puts actual SwiftData retirement in **Phase 5** (replace `CloudSyncJournalEngine`
   with the server `cw-sync` transport, gated on the OAuth2 overhaul —
   [design](2026-06-21-phase5-oauth-overhaul.md)). So Phase 4's exit
   is realistically "all reads + writes served by cw-store, SwiftData demoted to the sync
   replica," not zero `import SwiftData`. Also hard-gated on the device parity loop above.
8. **macOS Sweep in lockstep** — same `CarrierWaveData` shim; apply the same seams.
   **Caveat (2026-06-21):** "lockstep" is aspirational — CW Sweep currently has **no
   cw-store seam at all** (no `CwStoreProvider`/`FieldStore`/`CwStoreQSOMode`). All Phase 4
   read/write/analytics work is iOS-only today; the Sweep seams are unstarted, not partial.

## Verification reality (important)

- **Package loop (here):** `swift test --package-path swift/packages/CarrierWaveData
  --filter <Suite>` + `cargo test --workspace` — fast, no device.
- **App-target write-sink tests CANNOT run reliably in this environment** — device +
  simulator runners are broken (`SwiftDataError.loadIssueModelContainer` /
  `RequestDenied`). Re-confirmed empirically 2026-06-20: a targeted device run of
  `QSOWriteSinkTests` / `CwStoreMirrorTests` / `LoggingSessionManagerTests` on `theseus`
  failed twice for *environmental* reasons — first the device was **locked** (UI-runner
  launch denied → 79-test cascade), then a retry hit **"Failed to install the app …
  Connection with the remote side was unexpectedly closed."** The routed entities + the
  LoggingSession `SeamWriteBatch` writes compile (`xc build` green) but still need a
  device/CI `QSOWriteSinkTests`-shape pass + an on-device shadow-mode parity sweep before
  `on` mode is trusted. The package loop (cw-store + read sources) IS green here:
  `cargo test --workspace` + 28 RustStore read-source tests, 0 failures (2026-06-20).
- ~~**`CwFfi.xcframework` has no x86_64-sim slice**~~ — **RESOLVED 2026-06-20.**
  `build-xcframework.sh` now builds `x86_64-apple-ios` and `lipo`s it with
  `aarch64-apple-ios-sim` into one universal `ios-arm64_x86_64-simulator` slice
  (verified: `lipo -info` reports `x86_64 arm64`). An Intel/x86_64 CI runner can now
  link the simulator slice.

## Why partial routing is safe

`CwStoreMirror` dual-writes un-suppressed saves to cw-store in `shadow`/`on`, so every
un-routed write still reaches cw-store as a *follower*. Read cutover is therefore
already correct in `on`. The write seam only promotes follower → canonical (what lets
the SwiftData replica be removed at the Phase 4 exit). Deferring is safe; half-routing
a shared save is not.

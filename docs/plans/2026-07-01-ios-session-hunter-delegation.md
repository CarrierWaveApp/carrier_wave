# iOS Session + Hunter managers → delegate to the shared Rust core

Date: 2026-07-01
Status: **All coding phases DONE (A/B/C1/C2/D); remaining work is device verification + per-entity flips**
Owner: (unassigned)
Branch: `feat/ios-session-hunter-rust-delegation`

## Progress snapshot (2026-07-01)

- ✅ **Phase D (Rust) — complete & verified** (`cargo test --workspace` + clippy green): `SessionApi.record_conditions`,
  `save_average_wpm`, `split_at_utc_midnight`; the split runs on a new structured `rove_stop` table
  (Option C, cw-store schema v8) + `FfiRoveStop` FFI; Swift bindings staged (additive-only).
- ✅ **Phase B (reflection infra) — complete & host-verified** (9 `swift test` tests, no device): all 6
  `FfiReflector.hydrate` inverses + the `reflect` context-upsert wrapper (in-place update, mirror-suppressed).
- ✅ **Phase A + C1 (Hunter) — landed, app builds.** `ActivityLogManager` delegates `refreshTodayStats`
  (reads) + `logQSO` (writes) to `ActivityLogApi` under `.on` (→ `FfiReflector.reflect` → Swift side effects),
  SwiftData fallback in `.off`; `+GridObservation` raw-save fixed. `+RustDelegation`/`+Persistence` split.
- ✅ **C2 core (Session) — landed, app builds.** `LoggingSessionManager.logQSO` delegates to `SessionApi`
  under `.on` (non-contest; Rust omits contests), reflects the QSO, mirrors the count, keeps rove/upload/
  LiveActivity/widget Swift.
- ✅ **C2 remainder — landed 2026-07-03 (compile + package tests green).**
  - Lifecycle verbs (`pause`/`resume`/`finish`/`end`/`merge`/`delete`) delegate to `SessionApi` under
    `.on` via `LoggingSessionManager+RustLifecycle.swift`: seam pre-flush (carries spot comments,
    track points, a reopen's `endedAt = nil`) → Rust verb → mirror-suppressed in-place reflect;
    Swift path is the fallback on any failure. Reopen composes (local clear rides the resume
    pre-flush); delete keeps a spot-only seam batch (the Rust verb doesn't touch spots); merge
    applies identical SwiftData mutations and flushes suppressed.
  - `endSession` core delegates end → `split_at_utc_midnight` → `save_average_wpm`; reflected split
    sessions get their SwiftData QSOs/recordings re-pointed by UTC day. `recordConditions`
    delegates the fill-if-empty merge (session + POTA metadata).
  - Rove-stop table cutover: sink + passive mirror + `importAll` write-through
    (`projectRoveStops`), `importAll` re-run per app-version bump = backfill, post-split blob
    re-embed from the table (`hydrateRoveStops`); `roveStopsData` documented as transitional.
  - Reflect overloads for `LoggingSession`/`SessionSpot`/`ActivationMetadata` in
    `FfiReflector+Sessions.swift` (metadata keyed by park + UTC-midnight date).
- ⏳ **Remaining — device-gated:** `theseus` behavioral verification under `.on` (watch
  `CwStoreWriteLog`), then the per-entity two-device flips (Hunter first, Sessions second, never
  batched). Still Swift by design: `repairExistingPOTASessions` (one-time v1 repair), the live
  UTC-rollover timer, contest `logQSO`, and all network/LiveActivity/widget glue.

## Turnkey recipe for the device-gated remainder (A / C1 / C2)

These are app-target (`swift/ios/CarrierWave/Services/`) changes; they compile-check via `xc build` and
must be **behaviorally verified on-device** + flipped one entity at a time (physically needs hardware).

**Wiring available to build on:** `CwStoreProvider.shared.store()` (the app-group `FieldStore`);
`ActivityLogApi(store:)` / `SessionApi(store:)` (stateless, share that store); `FfiReflector.reflect(…, mirror:)`
(pass the app's `CwStoreMirror`); `CwStoreQSOMode.current` gate. Run every compound FFI call **off-main**
(`Task.detached { try api.… }` → `await MainActor.run { reflect + update @Observable }`) — see the Android
ViewModels (`withContext(Dispatchers.IO)`) as the reference.

1. **A — reads** (both managers): under `.on`, source `refreshTodayStats`→`ActivityLogApi.todayStats`,
   worked-today→`workedToday`, `loadActiveLog`→`activeLog`, `getSessionQSOs`→`SessionApi.sessionQsos`;
   SwiftData path under `.off`. Value-type results, no reflection.
2. **C1 — Hunter writes**: add the QSO + ServicePresence `reflect` overloads (per Phase B note), then route
   `ActivityLogManager` create/activate/switch/delete/logQSO through `ActivityLogApi` → `reflect` → refresh
   `@Observable` (`activeLog`, today counters, `dailyGoalReached`). Fix the `+GridObservation` raw `save()`.
   Keep Keychain/upload/notifications/FT8-enrichment Swift. Parity + device test → flip.
3. **D-tail — rove cutover** (unblocks C2 sessions): backfill each session's Swift `roveStops` into the
   `rove_stop` table via `replace_rove_stops`; rebuild `LoggingSession.roveStops` to read/write the table
   through FFI; drop the blob; decide rove-stop sync (own entity vs. re-embed — coordinate with Phase 5).
4. **C2 — Session writes**: LoggingSession/SessionSpot/ActivationMetadata `reflect` overloads, then route the
   lifecycle verbs + `logQSO` + `split_at_utc_midnight`/`save_average_wpm`/`record_conditions` through
   `SessionApi` → `reflect`. Work the coupling register (below), esp. the `endSession` ordered monolith.
   Parity + device test → flip. Do **not** batch the Hunter + Session flips.


## Goal

Stop iOS re-implementing session/hunter logging in Swift-over-SwiftData. Make
`LoggingSessionManager` (activation, 21 files/~4.4K LOC) and `ActivityLogManager` (hunter,
3 files/~600 LOC) delegate their portable logic — lifecycle, `logQSO`, reads, and the four
deferred algorithms — to the shared Rust `SessionApi` / `ActivityLogApi` in `cw-ffi`, which
**Android already runs on** (`HunterLogViewModel`, `ActivationViewModel`). This is the single
largest chunk of behavior still duplicated between the two platforms.

The Rust side is done (611 cw-ffi tests, clippy clean). This is the **iOS consumer rewire**
plus **three algorithm ports** (Phase D).

---

## What the investigation resolved

### A0 — entity-record canonicity is ALREADY DONE ✅
Both `ActivityLog` and `LoggingSession` record writes already route cw-store-canonical under
`CwStoreQSOMode.on` through registered `EntityWriteSink`s
(`EntityWriteSinkFactory.swift:54-58`; `EntityWriteSink.upsert/delete` writes cw-store first,
then does a mirror-suppressed SwiftData save for CloudKit). The seam, sinks, mode-gating, and
`FieldStore` provider (`CwStoreProvider.shared`) are all in place. **No new write-sink
machinery is needed.** One straggler to fix: `ActivityLogManager+GridObservation.swift:27`
does a raw `try? modelContext.save()` that bypasses the sink (passive-mirror follower, not
canonical) — one-line change to `EntityWriteSink.commitUpsert`.

### The central architectural issue — write-direction inversion 🎯
This is the fact that shapes the whole plan and was not visible before the investigation.

- **Today (`.on`):** the manager mutates the SwiftData `@Model` in memory → the seam
  *projects* it into cw-store (canonical for reads) → SwiftData is saved mirror-suppressed so
  **CloudKit still syncs it**. Direction: `SwiftData → cw-store`.
- **The Rust APIs** (`SessionApi.logQso`, `endSession`, `ActivityLogApi.createLog`, …) write
  **cw-store directly** and return an `FfiQso`/`FfiLoggingSession`/`FfiActivityLog`. They know
  nothing about SwiftData.

While SwiftData remains the **CloudKit sync replica** (true until Phase 5 server-sync retires
it), every write must still land in SwiftData or CloudKit sync breaks and rollback is
impossible. So delegating a *write* to a Rust API requires **reflecting the FFI result back
into the SwiftData replica** (mirror-suppressed, so it reaches CloudKit + updates the
`@Observable` UI but does not double-write cw-store). This "reverse reflection"
(`FfiQso → SwiftData QSO`, etc.) does **not exist today** — the importer is forward-only
(`SwiftDataStoreImporter.project` is SwiftData→Ffi). Building it is Phase B.

**Strategy decision.** Three options were considered:
- *S1 — logic-only delegation:* keep the SwiftData→cw-store seam for persistence, factor the
  Rust APIs into pure no-write compute functions and call only those. Rejected: forks the FFI
  surface (Android uses the compound store-writing APIs) and buys little.
- *S2 — store delegation + reverse reflection (CHOSEN):* call the compound Rust APIs (identical
  to Android), then reflect the returned Ffi record into the SwiftData replica mirror-suppressed.
  This is the true-parity path; the reflection layer is the explicit pre-Phase-5 bridge that
  gets **deleted** when Phase 5 retires the CloudKit replica.
- *S3 — wait for Phase 5:* clean, but blocks the cross-platform shift indefinitely. Rejected.

We take **S2**, sequenced reads-first so value ships before the reflection layer exists.

### Threading rule (non-negotiable) ⚠️
The Rust compound APIs are **synchronous UniFFI exports** that do real DB I/O. The managers are
`@MainActor`. Calling the APIs on the main actor blocks the main thread for the full call —
exactly the Android ANR that `withContext(Dispatchers.IO)` fixes (memory:
`uniffi-async-dispatcher`). **All FFI compound calls run off-main**, mirroring Android:

```swift
// Inside a @MainActor manager:
let input = buildInput(...)                 // build on main — reads @Model / cached flags
let result = try await Task.detached(priority: .userInitiated) { [api] in
    try api.logQso(input: input)            // Rust DB I/O OFF main
}.value
applyResult(result)                          // back on main: reflect + update @Observable
```
Never `MainActor.assumeIsolated` from an actor body (memory: `mainactor-assume-isolated-crash`);
`@MainActor` goes before the capture list. Share the SAME `FieldStore` (`CwStoreProvider.shared`)
so the API never drifts from the manager (both APIs are documented stateless — hold only
`Arc<FieldStore>`).

---

## Plan overview (phase dependency graph)

```
A (reads, both mgrs) ─┐
                      ├─► C1 (Hunter writes) ─► FLIP Hunter
B (reverse-reflect) ──┘                                 │
                                                        ▼
                      D (port 3 deferred algos) ─► C2 (Session writes) ─► FLIP Sessions
```

- **A** and **B** are independent and can run in parallel.
- **C1** (Hunter writes) needs A + B. Hunter has **no** deferred-algorithm coupling → ship first.
- **D** (POTA split, conditions, WPM ports) gates **C2** (Session writes).
- Each FLIP is one entity, verified, non-batched (per `2026-06-30-ios-ffi-migration.md`).

---

## Phase A — delegate READS (both managers, no reflection, low risk)

The managers still hand-roll SwiftData fetches/aggregation the Rust APIs already do. These are
pure reads from the already-canonical cw-store — no write-direction concern, safe under `.on`,
`SwiftData` fallback under `.off`. Ships immediately, proves the API wiring + off-main threading,
and deletes duplicated Swift aggregation.

**ActivityLogManager:**
- `loadActiveLog` (UserDefaults id + fetch) → `ActivityLogApi.activeLog()`
- `refreshTodayStats` (SwiftData `boundedFetch`) → `ActivityLogApi.todayStats(logId:)` → map
  `FfiTodayStats{qso_count,bands,modes}` onto `todayQSOCount/todayBands/todayModes`
- worked-today dedup → `ActivityLogApi.workedToday()`
- recent list → `ActivityLogApi.recentQsos(logId:limit:)`
- all logs → `ActivityLogApi.allLogs()`

**LoggingSessionManager:**
- `getSessionQSOs` → `SessionApi.sessionQsos(sessionId:limit:)`
- `loadActiveSession` stays Swift (UserDefaults restore + corruption-heal is iOS glue) but can
  cross-check against cw-store.

**Acceptance:** behavior-identical to the Swift path (parity test per read), off-main, no UI
regression on device. `currentProfile`/StationProfile lookups stay Swift (iOS-only).

---

## Phase B — reverse-reflection infrastructure

**Status (2026-07-01): LANDED + host-verified (9 tests, `swift test`, no device — CarrierWaveData
targets macOS 14).** `FfiReflector` in `CarrierWaveData/RustStore/FfiReflector.swift`:
- **Pure hydrators for all 6 synced `@Model` entities** — `hydrate(_:)` for `ActivityLog`, `QSO`,
  `LoggingSession` (75 cols), `ServicePresence`, `SessionSpot`, `ActivationMetadata` — each the
  faithful inverse of `SwiftDataStoreImporter.project`. Round-trip parity (`project(hydrate(ffi)) == ffi`,
  all-fields + nil variants) green.
- **Context-upsert wrapper** — `reflect(_ ffi: FfiActivityLog, into: context, mirror:)`: fetch-by-id +
  in-place update (preserves `@Observable` identity) or hydrated insert, saved mirror-suppressed
  (`beginSeamWrite`). Unit-tested (insert then same-id in-place update: one row, same object `===`).

**Remaining (mechanical, follows the ActivityLog pattern; do with each manager's wiring):** `reflect`
overloads for the other entities. **QSO must use in-place `applyFields`** (delete+insert would cascade
its `ServicePresence` relationship); `ServicePresence.reflect` links `qso` by fetching the QSO by id;
`LoggingSession`/`SessionSpot`/`ActivationMetadata` have no inbound SwiftData relationships (referenced
by UUID), so their `reflect` may reuse `hydrate` via delete+insert with the manager re-pointing held refs.

New package code (`CarrierWaveData/RustStore/`), unit-tested in isolation, no manager changes yet.

- `FfiReflector` — hydrate a SwiftData `@Model` from an Ffi record, upsert into a
  `ModelContext`, **mirror-suppressed** (`mirror.beginSeamWrite(for:)`), so the SwiftData row
  reaches CloudKit and updates `@Observable` state but does **not** re-project into cw-store
  (Rust already wrote it). Needed for: `FfiQso→QSO`, `FfiLoggingSession→LoggingSession`,
  `FfiActivityLog→ActivityLog`, `FfiServicePresence→ServicePresence`, `FfiActivationMetadata→
  ActivationMetadata`, `FfiSessionSpot→SessionSpot`.
- It is the inverse of `SwiftDataStoreImporter.project`. Build field-parity tests:
  `project(hydrate(ffi)) == ffi` round-trips exactly (reuse the existing `*Snapshot` value types,
  e.g. `ActivityLogSnapshot`, which already mirror the Ffi records).
- **ServicePresence note:** Rust `logQso` does its own upload routing (QRZ; POTA when POTA;
  LoFi/ClubLog are no-ops on the Rust side today). The returned QSO's presence rows must be
  reflected so the iOS upload pipeline (which reads `ServicePresence`) still fires. iOS keeps
  owning the actual upload network I/O; Rust only records intent.

**Acceptance:** round-trip parity tests green; a reflected write shows up in SwiftData +
CloudKit + cw-store with identical content, no double cw-store write (assert via
`CwStoreWriteLog`).

---

## Phase C1 — Hunter writes → `ActivityLogApi` (ship this first)

Rewrite `ActivityLogManager` write methods to: build the Ffi input on main → call the API
off-main → reflect the result into SwiftData (Phase B) → update `@Observable` state.

Map to API:
- `createLog` → `createLog(name:myCallsign:stationProfileId:grid:)`
- `activateLog`/`deactivateLog` → `activateLog(id:)` / `deactivateActiveLog()`
- `switchProfile` → `switchProfile(id:stationProfileId:grid:)`
- `updateGrid`/`updateLocationLabel` → same-named API methods
- `deleteLog` → `deleteLog(id:)`
- `logQSO` → `logQso(FfiLogQsoInput)` → `FfiLogQsoResult{qso, today, daily_goal_reached}`; map
  `today` onto the counters and `daily_goal_reached` onto `dailyGoalReached`. **Fix the
  GridObservation raw-save straggler here.**

`FfiLogQsoInput` fields the Swift side must supply (agent-confirmed): `log_id, callsign, band,
mode, frequency_mhz?, rst_sent, rst_received, their_grid?, their_park?, sota_ref?, notes?,
name?, state?, country?, power?, my_rig?, station_profile_name?, upload_qrz, upload_lofi,
upload_clublog, daily_goal`. Power/rig/profile-name are host-resolved from `StationProfile`
(stays Swift). Upload flags come from the cached Keychain-derived booleans (stays Swift).

**Stays Swift (iOS glue):** StationProfile/Keychain config, `markForUpload` network pipeline,
`QSOLedger`/`NotificationCenter.didLogQSO`, `ActivityDetector`, CoreLocation grid observation,
FT8 DXCC stamp + `backfillFT8Lookup` (async callsign enrichment). FT8's post-log direct saves
must be routed through the sink/reflector, not raw `context.save()`.

**Verify:** parity (Rust path vs current Swift path over a fixture log → identical rows +
today-stats + worked-today) → device test on `theseus` (create → quick-log → dupe badge →
switch profile → today stats → delete; watch `CwStoreWriteLog`) → **FLIP** (per-entity
verification protocol below). Hunter has no G2/Phase-D dependency.

---

## Phase D — port the deferred algorithms to Rust (gates C2)

Decision (2026-07-01): port to Rust for Android parity, not Swift post-hooks. Scope per the
investigation. Each: new cw-ffi code + parity tests + binding regen
(`rust/cw-core/scripts/build-xcframework.sh` for Apple, `android/build-rust.sh` for Kotlin).

**Status (2026-07-01): #1, #2, #3 all LANDED + tested (Rust); #4 dropped. Option C (structured
rove-stop storage) landed as schema v8 to unblock #1. Remaining: iOS-side rove-stop cutover +
binding stage-into-package, both device-gated with C2.**

2. **NOAA conditions fill-if-nil merge** — ✅ **DONE.** `SessionApi.record_conditions(session_id,
   FfiConditionsInput) -> Option<FfiConditionsResult>` (`session_api.rs`). Fills the session row
   (text nil-only; structured solar/weather blocks guarded by `hasSolarData`/`hasWeatherData`)
   and, for POTA activations, the `(primary_park, UTC-day)` `ActivationMetadata` row (text fill on
   nil-**or-empty-string**, the stricter Swift rule; find-or-create). Network fetch stays Swift.
   8 parity tests green.
3. **WPM averaging** — ✅ **DONE.** `SessionApi.save_average_wpm(session_id, wpm_values: Vec<i32>)
   -> Option<FfiActivationMetadata>`. Integer-truncating average (matches Swift `sum/count`),
   keyed `(primary_park, UTC-day-of-startedAt)`, **always overwrites** `average_wpm` (vs #2's
   fill-if-nil). Swift keeps the `\d+ WPM` regex and passes parsed values in. Returns the metadata
   row (not just the int) so the host can reflect it. Tests: empty/missing/no-park → None,
   truncation, overwrite, multi-park→primary.
1. **POTA UTC-midnight split** — difficulty **M**. ✅ **DONE via Option C (structured rove-stop
   storage).** `SessionApi.split_at_utc_midnight(session_id) -> Vec<FfiLoggingSession>`: groups the
   session's QSOs (incl. hidden — new `fetch_all_qsos_for_session`) by UTC day, clips the original's
   `endedAt`/`qsoCount`, clones a completed session per extra day (faithful `createSplitSession`
   clone-defaults: copies the init subset, derives `programs` from `activationType` alone — dropping
   extra programs + sotaRef/wwffRef/stationCallsign/contest/conditions, exactly as Swift does), and
   reassigns that day's QSOs + WebSDR recordings + rove stops. Returns all resulting sessions
   (original first) for the host to reflect. 4 parity tests (no-op cases, two-day bounds/reassign,
   programs-from-activationType, rove clip + park-at-midnight).
   **The parity blocker was solved by doing Option C (below), not by encoding the Swift blob in Rust.**
   Still Swift-side: the live UTC-rollover timer + service restarts (`+UTCDayBoundary`), and
   `repairExistingPOTASessions` (one-time v1-split fix) — port alongside C2 or as a follow-up.

   **Option C — structured `rove_stop` table (LANDED, schema v8).** New `cw-store` `rove_stop` table
   (Unix-seconds, FK to session) + `RoveStop` struct + store API (`upsert`/`fetch_rove_stops`/
   `delete_rove_stops_for_session`/`replace_rove_stops`) + `FfiRoveStop` FFI + `RoveStop` observation
   case. Replaces the un-portable Swift-`JSONEncoder` `rove_stops_data` blob (Date-as-2001-double) as
   the source of truth; the blob column stays for the iOS transition. **Remaining iOS cutover (device-
   gated, with C2):** (a) backfill — iOS decodes each session's `roveStops` (its existing property)
   and writes them to the table via `replace_rove_stops`; (b) rebuild `LoggingSession.roveStops` to
   read/write the table through FFI instead of the blob; (c) drop/deprecate `rove_stops_data`;
   (d) **sync decision** — rove stops become their own synced entity vs. iOS re-serialises the table
   into the LoggingSession sync record (coordinate with Phase 5). Android gets rove support for free
   off the table.

**Dropped from this batch (recommended amendment — see Decisions):**
4. **sortedSpots ordering + unread divider** — difficulty M (S without needs-sort). The
   investigation found this is a **pure SwiftUI view-model computation in `ActivityLogSpotsList`
   with NO persistence effect**, coupled to `EnrichedSpot`/`SpotNeedsMatcher` (the `.needs`
   experiment), which has **no Rust analog**. Porting it now buys no cross-platform-persistence
   parity (nothing is written) and drags in the entire needs-enrichment engine. **Recommend
   leaving it Swift and porting it later alongside spot-needs enrichment** — see Decisions.
   (The `.recent`/`.frequency` sorts + unread divider are enrichment-independent if we ever do
   want a cheap partial port.)

---

## Phase C2 — Session writes → `SessionApi` (after D)

Same shape as C1 but against `SessionApi` and materially more coupled. `startSession` stays
platform-specific (per `SessionLifecycleAPI`'s doc — POTA/TOTA/WebSDR auto-start knobs); delegate
`pauseSession/resumeSession/finishSession/endSession/reopenSession/mergeSessions/deleteSession/
logQSO`.

`FfiSessionLogInput` (agent-confirmed) carries the full QSO field set + `session_id`, override
freq/mode/timestamp, and `upload_qrz/upload_pota(gated to POTA sessions)/upload_lofi/clublog`.
`FfiSessionLogResult{qso, qso_count}` → reflect the QSO + update the session's `qso_count` on the
`@Observable` `activeSession` so Logger/LiveActivity/widget/Watch update.

### Coupling-risk register (must be handled explicitly; from the Sessions investigation)
- **`endSession` is a load-bearing ordered monolith** (`+SessionManagement.swift:10-69`):
  endLiveActivity → flushTrackPoints → POTA split → `activeSession=nil` → `saveAverageWPM`
  (result folded into the same `SeamWriteBatch`) → `commitSessionSplit` → autoShare. Delegation
  must feed WPM + split as FFI steps *or* run them Swift-side before the FFI end call. The
  current `SeamWriteBatch` atomicity (all-or-nothing) is lost if split into separate FFI calls —
  decide whether `SessionApi.endSession` should accept split+WPM as one compound call.
- **WPM metadata rides the end batch** — with #D3 ported, `endSession` calls `save_average_wpm`
  as part of the end sequence.
- **`logQSO` count-then-write ordering + rollback** (`+QSOManagement.swift:107-134`):
  `incrementQSOCount()` precedes the write; failure does `modelContext.rollback()`. The FFI
  returns the canonical `qso_count` — reflect it; on FFI error, don't touch SwiftData.
- **ServicePresence stamped before the write** (`markForUpload`) — Rust owns routing now;
  reflect presence rows, keep upload network I/O in Swift.
- **FT8 post-log saves bypass the seam** (`+FT8QSOLogger.swift:73`) — route through the
  reflector/an `updateQso` FFI, not raw `context.save()`.
- **Spot comments folded onto the session at pause/end** (`session.spotComments = …`) — pass as
  an input to the pause/end FFI call (they live on the session row, not separate).
- **`connectRadio()` reads `activeSession?.radioItemID`** — ordering constraint: FFI creates
  session → reflect to SwiftData → set `activeSession` → `connectRadio()`.
- **`finishSession` (paused) asymmetry** — skips split/WPM/QRT-spot vs active end; preserve.
- **Continuity `adopt()` duplicates the activation side-effect sequence** — reconcile so LAN/
  CloudKit handoff and normal activation share one path.

### Stays Swift (the boundary)
`+LiveActivity`, `+Radio`/`+FrequencyAndMode` (CAT/BLE), `+TOTA` GPS track recording,
`+Spotting`/`+SpotDispatch` (POTA/RBN network, comment polling), `+Continuity` LAN handoff,
UserDefaults active-session restore. These call *into* `SessionApi`; never the reverse.

---

## Per-entity FLIP + verification protocol (applies to every C-phase flip)

1. Parity test: Rust path vs current Swift path over a fixture, assert identical resulting
   rows/counts/stats (the `rust-swift-parity` acceptance bar).
2. Device test on `theseus` under `.on`, watching `CwStoreWriteLog` for divergence.
3. Flip the entity to Rust-authoritative; keep the Settings→Experiments `CwStoreQSOMode` `.off`
   picker as the per-entity rollback (takes effect next launch).
4. One entity per flip — **do not batch** Hunter and Session flips.
5. **macOS CW Sweep stays `.off`.** It shares `LoggingSessionManager`'s package seams via
   `MacSessionManager` but lacks the `.on` read/write routing (`rust-migration-status.md`
   step 10). Guard the shim `#if os(iOS)` / mode-gated so Sweep is unaffected.
6. G1 (two-device QSO sync) is **already verified** (2026-07-01, user-confirmed) — flips are not
   stacking on an unverified base.

---

## First shippable PR (smallest safe increment)

Phase A for **ActivityLogManager only**: point `refreshTodayStats`/`workedToday`/`loadActiveLog`/
`recentQsos`/`allLogs` at `ActivityLogApi` off-main, with SwiftData fallback under `.off`, plus
the GridObservation raw-save fix. No writes change, no reflection needed. Parity + device test.
This proves API wiring + threading end-to-end on the smaller manager before any write cutover.

---

## Decisions / open items

- **Recommend dropping sortedSpots (D4) from this effort** and porting it later with spot-needs
  enrichment. It's a view-only computation with no persistence-parity payoff and no Rust needs
  engine to sort against. (You previously said "all four to Rust" — flagging because the
  investigation showed #4 is a different animal from #1-3.) **Need your call.**
- **`SessionApi.endSession` compound vs stepwise:** should end accept POTA-split + WPM as one
  atomic FFI call (preserves `SeamWriteBatch` all-or-nothing), or keep them as ordered Swift-
  driven FFI steps? Recommend compound for atomicity; costs a wider `endSession` signature.
- **Reflection layer lifetime:** Phase B is an explicit pre-Phase-5 bridge; delete it when server
  sync retires the SwiftData CloudKit replica. Track it so it doesn't ossify.

## Ordered execution

1. **First PR:** Phase A / Hunter reads + GridObservation fix.
2. Phase A / Sessions reads. Phase B reverse-reflection infra (parallel).
3. **Phase C1** Hunter writes → parity → device → **FLIP Hunter**.
4. **Phase D** port POTA-split + conditions + WPM (skip sortedSpots pending decision).
5. **Phase C2** Session writes (coupling register) → parity → device → **FLIP Sessions**.

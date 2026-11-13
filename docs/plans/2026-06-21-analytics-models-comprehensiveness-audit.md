# Analytics models — comprehensiveness audit

**Date:** 2026-06-21
**Goal:** make every cw-store analytics model carry **all** fields its consuming
actor needs, so each consumer routes onto `AnalyticsReadSource` in `.on` with **no
data loss** and **no residual SwiftData scan** for the covered surface.
**Companion:** [rust analytics surface design](2026-06-20-rust-analytics-surface-design.md)
(the original "first cut" that deliberately deferred the gaps below).
**Current status + cross-platform next steps:** [rust-migration-status.md](rust-migration-status.md).

## Why fields were missing

The surface shipped as a deliberate first cut — SQL-trivial aggregates only. Per-row
detail (grid callsign/band/mode), per-activation award inputs, WAS per-state
counts/callsigns, DXCC bands, and brag distance/streak/window were left SwiftData-side
to land the layer incrementally. This audit closes those gaps.

## Per-model gap table

| Model | Consumer | Has | Missing (consumer needs) | Tractability |
|-------|----------|-----|--------------------------|--------------|
| **GridTile** | GridOverlayDataActor / GridTrackerDetailView | tile,count,confirmed,lastQSO | **callsigns, bands, modes** (per tile) | ✅ pure SQL `group_concat(DISTINCT)` — **DONE this pass** |
| **DxccWorked** | DXCC needs, map entity rollup | dxccID,name,lat,lon,count | **bands** (per entity — the original catalog spec lists it) | ✅ pure SQL `group_concat(DISTINCT band)` |
| **AnalyticsCounts** | StatsComputationActor | qsos,bands,grids,entities,parks,confirmed | qrz-vs-lotw split, icloud-imported, with-grid/dxcc/freq/park, unique hunter & freq-group | ✅ pure SQL `COUNT`/`COUNT(DISTINCT)` w/ predicates |
| **ActivationRollup** | POTAAwardsActor | park,op,utcDate,unique,total,successful | per-activation **bands** + **dxcc** (for laPorta/sixPack/dxEntities) | ✅ pure SQL group_concat; states still need cache (below) |
| **WasSummary** | StatsComputationActor WAS drilldown | allStates, perMode states | **per-state count**, **per-state callsigns**, QTH-vs-all source split | ⚠️ medium — SQL group_concat + count, but source split needs `my_grid` filter |
| **BragPeriodMetrics** | BragSheetComputationActor | 13 totals | distance, streaks, records, geographic, speed/rate, new-this-period | ⚠️/❌ mixed (see below) |
| countBy, stateCounts, ParkRollup, ServicePresenceCount, SessionEquipment/Combo | dashboard / MyParks / presence / equipment | — | none material | ✅ already comprehensive |

## Architecturally hard (NOT pure SQL — need a design decision)

1. **POTAAwards `statesActivated`** — maps park → US states via `POTAParksCache`,
   whose data is **downloaded from pota.app** (~50k-park CSV, cached as JSON) with the
   state set living in each park's `locationDesc` (`"US-WY,US-MT"`), *not* a QSO column.
   **Decision (2026-06-21): port it.** Concrete design:
   - New **`pota_park` table** in cw-store (`reference TEXT PK, name, location_desc,
     entity_id, lat, lon, grid, is_active`) — **schema v4 migration**.
   - **Population path:** the existing `POTAParksCache` download writes through to
     cw-store (new `upsert_pota_parks` FFI, batched) so Rust has the same dataset.
   - **Awards aggregate:** a dedicated `pota_awards(query, min_qsos)` cw-store fn that
     groups activations (as `activation_rollup` does) and JOINs `qso.park → pota_park`
     to derive states (mirroring `statesForPark`'s grid→state fallback), plus
     per-activation band sets + per-band counts (laPorta / sixPack) + dxcc sets
     (dxEntities). Then route `POTAAwardsActor`.
   - This is its own focused session (schema migration + population + parity), tracked
     as task #10. Until then POTAAwards stays SwiftData (correct, just not cut over).

   Also: extend `ActivationRollup` with per-activation `bands`/`dxccs` as part of this
   batch (POTAAwards-coupled, not the "tractable" batch — the current rollup already
   serves `StatsComputationActor`'s activation counts).
2. **Brag distance / records** — needs Maidenhead→coord great-circle. cw-domain has the
   coords; add a `cw_grid_distance_km` SQLite UDF (medium). Furthest-contact records =
   per-QSO distance then MAX — do in Rust over minimal columns.
3. **Brag streaks / peak-rate windows** — sequential day-gap / sliding-window math, not a
   `GROUP BY`. Doable in Rust (fetch distinct dates / timestamps, fold) but its own slice.
4. **EquipmentItemDetail per-item band/mode/distance breakdown** — a deeper consumer not
   yet modeled at all; new `session_item_detail` aggregate.

## Execution order

1. **GridTile callsigns/bands/modes** — ✅ done (cw-store + ffi + test green).
2. **Batch the pure-SQL extensions** (one xcframework regen for all): DxccWorked+bands,
   AnalyticsCounts+extras, ActivationRollup+bands/dxcc, WasSummary+counts/callsigns.
   Each: cw-store struct+SQL+test → cw-ffi DTO → Swift DTO+oracle+parity.
3. **Route** GridOverlay (clean now), re-route Stats (richer counts), POTAAwards
   (bands/dxcc-backed awards; states stay SwiftData w/ a flag).
4. **Hard slices** (separate sessions, each a design decision): parks-cache port for
   POTAAwards states; brag distance UDF; brag streak/window; equipment item-detail.

## Verification

All of step 1–2 verify in the **package loop** here — `cargo test --workspace` +
`swift test --filter AnalyticsReadSourceTests` — no device. Routing (step 3) is
app-target, device-gated like the rest of Phase 4.

## Progress log — 2026-06-21

All commits below are on `main`, each verified before commit (cw-store/cw-ffi
`cargo test` + clippy, `swift test --filter AnalyticsReadSourceTests`, iOS app
`xcodebuild build`). The analytics routing is dormant until `.on` on-device, by
design — same gate as the write seam.

**Done & committed:**

- **Consumer routing (5 of 7)** — `f17e97c3`:
  MyParksView→`parkRollup`, AsyncServicePresenceCounts→`servicePresenceCounts`,
  EquipmentStatsActor→`session*Rollup` (clean swaps), StatsComputationActor→
  `distinctCounts` overlay, GridOverlayDataActor→`gridTiles` (lossless — see below).
- **GridTile + DxccWorked comprehensive** — `f17e97c3`: GridTile gains
  `callsigns`/`bands`/`modes` (so GridOverlay keeps `GridTrackerDetailView`'s
  callsign search + band display under `.on`); DxccWorked gains `bands`.
  End-to-end: cw-store SQL (`group_concat(DISTINCT)`, split+sorted) → cw-ffi DTO →
  regenerated `CwFfi+Generated.swift` → Swift DTO + `AnalyticsAggregator` oracle +
  parity.
- **AnalyticsCounts comprehensive** — `1c4dd067`: adds `qrz_confirmed`,
  `lotw_confirmed`, `with_grid`, `with_park`, `with_dxcc`, `unique_callsigns`;
  StatsComputationActor's `.on` overlay now sources all of them.
- **pota_park foundation (schema v4)** — `e9bad5ee`: `PotaPark` + DDL + batched
  `upsert_pota_parks` (single tx) + count/fetch + idempotent v4 migration. The data
  dependency for POTAAwards state parity (park→states lives in the pota.app
  download, not a QSO column). Isolated commit — migration is the riskiest piece.

**Re-scoped while executing:** ActivationRollup's bands/dxcc detail is
POTAAwards-coupled (the current rollup already serves StatsComputationActor's
activation counts), so it moves to the POTAAwards port, not the "tractable" batch.
WasSummary turned out architectural too — its consumer needs a per-(source × mode ×
state) structure with counts + callsigns + a QTH-grid filter, not a `group_concat`.

**POTAAwards port (continues from the pota_park foundation):**

1. ✅ **cw-ffi pota_park surface** — `entities/pota_park.rs`: `FfiPotaPark` DTO +
   `From` both ways + `upsert_pota_parks`/`pota_park_count`/`fetch_pota_park` on
   `FieldStore` (reference data — no observation `notify`). Regenerated
   `CwFfi+Generated.swift` + xcframework; cw-ffi build/clippy/test + full
   `cargo test --workspace` (218+) green, `swift build` on CarrierWaveCore green.

3. ✅ **`pota_awards` aggregate + grid→state sub-port (steps 3 & 4)** — faithful
   Rust fold port of `POTAAwardsActor` + `POTAAwardsComputation` in
   `cw-store/src/pota_awards.rs`. Fetches park-QSO columns once (newest-first,
   metadata included for raw totals) and folds in Rust — per-activation
   `callsign|band|mode|park` dedup, two-fer split, per-park band sets (LaPorta),
   6m/six-pack, rover, repeat-offender, one-dxcc-per-activation, kilo/near-kilo,
   park-to-park, `statesActivated` via `pota_park.location_desc` **plus** the
   Maidenhead grid fallback. Grid fallback is the step-4 sub-port:
   `cw-domain/src/us_grid_state.rs` (`grid_to_us_state`, port of
   `POTAClient+GridLookup.swift`). 16 cw-store fold tests + 5 grid tests; cw-ffi
   `FfiPotaAwards`/`FfiNearKiloPark` + `pota_awards(query)` method → regenerated
   bindings.
   Verified: `cargo test --workspace` + clippy clean, `swift build` green.
4. ✅ **WAS250 aggregate** — `Store::was250()` in `analytics.rs`, faithful port of
   `POTAAwardsActor.computeWAS250` + `WAS250Computation`: the America 250 award over
   non-hidden 2026 QSOs with a `state` (the 2026 UTC window is baked in as award
   definition, mirroring the Swift hard-code), bucketed into states-worked / CW /
   Phone / Digital by the `cw_mode_family` UDF, plus the diagnostic pipeline counts
   (total / metadata-excluded / with-state / with-valid). 2 tests; cw-ffi `FfiWas250`
   + `was250(query)` → regenerated bindings. Both halves of `POTAAwardsActor.Result`
   are now in Rust.
   Verified: `cargo test --workspace` (cw-domain 223 / cw-store 128 / cw-ffi 11)
   + clippy clean, `swift build` on CarrierWaveCore green.

2. ✅ **POTAParksCache write-through (iOS)** — `POTAParksCache+CwStore.swift`:
   `writeThroughToCwStore(_:force:)` mirrors the downloaded park set into cw-store's
   `pota_park` table via `CwStoreProvider`. Wired into all four load/refresh sites
   (binary fast-path, disk-CSV, `forceRefresh`, `downloadAndUpdateStatus`); `force`
   gates it so a fresh network download always upserts while a cache load upserts
   only when the table is empty — a normal launch never rewrites ~50k rows. Gated on
   the same flags as the QSO write seam (`.rustStoreQSO` + `CwStoreQSOMode != .off`).
   **macOS N/A** — CW Sweep has no cw-store seam (no `CwStoreProvider`/`FieldStore`).
   Verified: iOS app builds clean (simulator), swiftformat + swiftlint clean.

5a. ✅ **Swift parity surface (`POTAAwards` + WAS250)** — `AnalyticsReadSource`
   gains `potaAwards(query:)` + `was250(query:)`; `RustAnalyticsReadSource`
   (`+POTAAwards` extension) serves them from cw-store; `AnalyticsAggregator`
   (`+POTAAwards` extension) is the pure-Swift oracle that re-derives the award math
   independently. New result types `POTAAwardsResult` / `WAS250Result` /
   `NearKiloParkRow`. Cross-impl parity tests (`AnalyticsPOTAAwardsParityTests`)
   assert Rust == oracle for both; `statesActivated` exercises the `pota_park` cache
   path (grid fallback is covered by cw-domain's `us_grid_state` unit tests).
   Verified: CarrierWaveData package builds + both parity tests green; swiftformat +
   swiftlint clean.

5b. ✅ **Route `POTAAwardsActor`** — `compute(container:)` now overlays cw-store in
   `.on`: `computeFromStore` maps `potaAwards`/`was250` into `POTAAwardsProgress` /
   `WAS250Progress`, falling back to the SwiftData scan otherwise (same overlay shape
   as `GridOverlayDataActor`). Dormant until `.on` on-device; parity gated by
   `AnalyticsPOTAAwardsParityTests`. Verified: iOS app builds clean (simulator),
   swiftformat + swiftlint clean.

**POTAAwards port — COMPLETE.** Both halves of the award screen now route to the
Rust `pota_awards` / `was250` aggregates under `.on`, backed by the `pota_park`
write-through, with cross-impl parity tests as the acceptance bar.

**Remaining — other architectural models (task #10):**

- **WasSummary drilldown** — ✅ aggregate + parity done: cw-store `was_drilldown`
  (per source×mode×state → count + distinct callsigns; `source` = all/qth via the
  park filter; rollups for all-modes and all-source) + cw-ffi `FfiWasDrilldownRow`
  + `RustAnalyticsReadSource.wasDrilldown` + `AnalyticsAggregator` oracle +
  `AnalyticsWASDrilldownParityTests`. Design decision: callsigns are returned
  distinct-sorted (the consumer takes `Set(...).sorted()` anyway). **Routed:**
  `StatsComputationActor` overlays `wasData` from `wasDrilldown` under `.on`
  (`+RustOverlay` extension, alongside the headline-counts overlay). ✅ COMPLETE.
- **Brag**: ✅ distance (`brag_distance_stats`, #2) + ✅ streaks (`brag_streaks`, #3) + ✅
  geographic (`brag_geographic`, #4) done — full stat catalog ported. Remaining: route
  `BragSheetComputationActor` (#5).
- ✅ **EquipmentItemDetail** per-item band/mode/distance breakdown — DONE (`session_item_detail`).

**Not analytics, still open (Phase 4):** LoggingSession write leftovers
(`mergeSessions`, `+Continuity`, repair loop); importer trigger + end-to-end
parity test (the exit-criterion code). See the
[phase 4 cutover status](2026-06-20-phase4-cutover-status.md).

## Status snapshot — 2026-06-21 (all on `main`, each verified before commit)

**Done & shipped this pass:**

| Slice | Commits | State |
|-------|---------|-------|
| GridTile + DxccWorked comprehensive | `f17e97c3` | routed (`.on`) |
| AnalyticsCounts comprehensive | `1c4dd067` | routed (`.on`) |
| pota_park table (schema v4) | `e9bad5ee` | foundation |
| **POTAAwards port** (FFI → aggregate → grid→state → parks write-through → parity → route) | `08c44077` `adf9bfc4` `d71e5866` `fbf72df2` `2bb831dd` `bd9566fd` | **COMPLETE, routed (`.on`)** |
| **WAS drilldown** (`wasData`) | `51255382` `c57067ed` | **COMPLETE, routed (`.on`)** |
| **EquipmentItemDetail** (`session_item_detail` + `cw_grid_distance_km` UDF) | _this pass_ | **COMPLETE, routed (`.on`)** |
| **Brag distance metrics** (`brag_distance_stats`) | _this pass_ | **aggregate + parity COMPLETE; routing deferred to step #5** |
| **Brag streaks** (`brag_streaks`: on-air / per-mode / activation) | _this pass_ | **aggregate + parity COMPLETE; routing deferred to step #5** |
| **Brag geographic** (`brag_geographic` + `cw_domain::continent` + `cw_continent` UDF) | _this pass_ | **aggregate + parity COMPLETE; routing deferred to step #5** |
| **Brag records/volume/fun** (`brag_records` + `cw_mode_canonical` UDF) | _this pass_ | **aggregate + parity COMPLETE; routing deferred to step #5** |
| **Brag session-sequence** (`brag_session_stats`, fetch-and-fold) | _this pass_ | **aggregate + parity COMPLETE; routing deferred to step #5** |
| **Brag POTA** (`brag_pota`) | _this pass (parallel subagent)_ | **aggregate + parity COMPLETE; routing deferred to step #5** |
| **Brag averageRST + club** (`brag_average_rst` + `cw_rst_s` UDF + `worked_member_callsigns`) | _this pass (parallel subagent)_ | **aggregate + parity COMPLETE; routing deferred to step #5** |

All routing is dormant until `CwStoreQSOMode == .on` on-device (same gate as the
write seam). Verification per slice: Rust `cargo test --workspace` (cw-domain 223 /
cw-store 130 / cw-ffi 11) + clippy `-D warnings`; CarrierWaveData parity tests
green; iOS app builds clean (simulator); swiftformat + swiftlint clean.

**Established slice recipe** (follow for every remaining aggregate):
cw-store struct + SQL/fold + Rust tests → cw-ffi DTO + method → `build-xcframework.sh`
regen → CarrierWaveData result type + `RustAnalyticsReadSource` method + an
`AnalyticsAggregator` oracle (independent re-derivation) + `Analytics*ParityTests`
(`Rust == oracle`) → route the consuming actor with an `.on` overlay + fallback.

## Next steps (ordered; each its own focused session)

1. ✅ **EquipmentItemDetail** — DONE this pass. `session_item_detail(name)` in
   `analytics.rs` (totals, distinct entities, distance MIN/MAX/AVG, per-band/per-mode
   tallies) over the `qso ⋈ logging_session` match (rig/antenna/key/mic, exact match,
   `qso_count > 0`, metadata excluded but **not** hidden — mirrors the consumer). Landed
   the `cw_grid_distance_km(grid_a, grid_b)` UDF here (wraps `cw_domain::maidenhead`
   great-circle; registered beside `cw_lower`/`cw_mode_family`). `FfiSessionItemDetail`/
   `FfiItemTally` + `session_item_detail` method → regenerated bindings → Swift
   `SessionItemDetailResult`/`ItemTallyRow` + `RustAnalyticsReadSource` +
   `AnalyticsAggregator` oracle + `AnalyticsSessionItemDetailParityTests` (distance fields
   compared with tolerance — Rust/Swift libm trig differs in low ULPs). Routed:
   `EquipmentItemDetailActor.computeStats` overlays cw-store under `.on` (sessions/paired
   stay SwiftData); the `.off` path was re-pointed from `CLLocation` to
   `MaidenheadConverter.distanceKm` so both modes + the oracle share one haversine
   (sub-0.5 % display shift), and its band/mode tie-ordering made deterministic.
   Verified: `cargo test --workspace` + clippy clean, package parity tests green, iOS app
   builds (simulator), swiftlint clean.

2. ✅ **Brag distance metrics** — DONE this pass. `brag_distance_stats(query)` in
   `analytics.rs`: furthest overall / QRP / CW / CW+QRP / perfect-RST (each a filtered
   `ORDER BY cw_grid_distance_km(...) DESC, callsign ASC LIMIT 1`), per-band (window
   `ROW_NUMBER`), average (`AVG` over computable distances), lowest-power (`ORDER BY power`),
   best-watts-per-mile (`ORDER BY power/(d·mi)`). All bounded SQL — no row loading. FFI
   design call **resolved: a flat `FfiBragDistanceStats`** record (the Swift side maps each
   field to its `BragSheetStatValue` case), not a tagged union. `BragContact`/
   `BragBandRecord`/`BragPowerContact`/`BragEfficiency` DTOs → Swift
   `BragDistanceStatsResult` + `RustAnalyticsReadSource` + `AnalyticsAggregator` oracle +
   `AnalyticsBragDistanceParityTests` (distances compared with tolerance — Rust/Swift trig
   differs in low ULPs; callsign/band exact). **Not routed yet** — `BragSheetComputationActor`
   routing waits on steps 3–4 covering the rest of its catalog (step #5). Verified:
   `cargo test --workspace` + clippy clean, package parity green, iOS app builds, lint clean.

3. ✅ **Brag streaks** — DONE this pass. `brag_streaks(query, today)` in `analytics.rs`:
   on-air (any visible QSO), per-mode (CW/Phone/Digital), and activation (≥10-unique-QSO
   park days) day streaks. Distinct active days via SQL `strftime` (bounded by day count),
   folded through `cw_domain::streak` (semantically equal to the actor's inline
   `computeStreakFromDates`). **Decision: on-air day-bucketing normalized local→UTC** (Swift
   used `Calendar.current`; now consistent with all other brag day-stats + DST-correct).
   `today` is a parameter (the store can't read the clock); cw-ffi takes a `YYYY-MM-DD`
   string → `NaiveDate`. `StreakValue`/`ModeStreak`/`BragStreaks` → Swift `BragStreaksResult`
   + `RustAnalyticsReadSource` + `AnalyticsAggregator` oracle (UTC fold) +
   `AnalyticsBragStreaksParityTests` (integer-exact). No "peak-rate window" stat exists in
   the actor's catalog — the streak set is complete. **Not routed** (step #5). Verified:
   `cargo test --workspace` + clippy clean, package parity green, iOS app builds, lint clean.

4. ✅ **Brag new-this-period + geographic rollups** — DONE this pass.
   `brag_geographic(query)` in `analytics.rs`: `dxcc_entities`, `new_dxcc_entities`
   (all-time-earliest-per-entity vs period-start, via a doubled-`where` subquery),
   `states_provinces` / `was_states` (reuse `NORMALIZED_STATE` + the 50-state list),
   `grid_squares` (`COUNT(DISTINCT SUBSTR(their_grid,1,4))`), `continents` /
   `most_continents_day` (the new `cw_continent` UDF over the **`cw_domain::continent`** port
   of `ContinentMapper` — 6 hand-curated sets + NA→SA→EU→AF→AS→OC precedence, copied
   verbatim). `FfiBragGeographic` → Swift `BragGeographicResult` +
   `RustAnalyticsReadSource` + `AnalyticsAggregator` oracle (continent sets re-duplicated in
   the package, as `validUSStates` is) + `AnalyticsBragGeographicParityTests` (integer-exact;
   exercises the `date:2026` period for new-this-period). Verified: `cargo test --workspace`
   + clippy clean, package parity green, iOS app builds, lint clean.

5. **Finish the Brag catalog, then route `BragSheetComputationActor`.** The original
   audit under-scoped this: the actor has **11 stat categories (~58 stats)**, not just
   distance/streaks/geographic. Ported so far: period-metrics + distance + streaks +
   geographic + records (≈ all GROUP-BY-shaped stats). **Remaining before a route that
   actually retires the SwiftData scan:**
   - ✅ **Session-sequence stats** — DONE (`brag_session_stats`, fetch-and-fold).
   - ✅ **POTA-brag** — DONE (`brag_pota`: parks activated/hunted, P2P, best-activation,
     new-parks; largest-Nfer was in session-stats).
   - ✅ **Misc** — DONE (`averageRST` via `brag_average_rst` + `cw_rst_s` UDF; `fastestCWSpeed`
     is a `.noData` stub, nothing to port).
   - ✅ **Club stats** — DONE via the **parameterized aggregate** `worked_member_callsigns(query,
     members)`: the app passes its club member-callsign list in; the store returns the worked
     members (distinct, uppercased, sorted), and the app derives `clubMembersWorked` (count) +
     `clubsRepresented` (maps the list → clubs app-side via `clubsByCallsign`).

   **All brag aggregates exist + parity-tested.**
   - ✅ **ROUTED** — `BragSheetComputationActor.computeFromStore` (`+RustOverlay`) serves every
     enabled stat from the aggregates under `.on` (no SwiftData scan). The period is passed as a
     `ParsedQuery.date_window` (`(Option<i64>, Option<i64>)` field ANDed by `compile_where`) —
     the UTC instant range `[start, now]` the day-granular DSL can't express; the 9 brag FFI
     methods gained `start/end: Option<i64>` (Swift read-source defaults them to `nil`). `.off`
     aligned: `distanceKm` → `MaidenheadConverter.distanceKm`, on-air streak bucketing → UTC.

   **`BragSheetComputationActor` is the last analytics consumer — analytics routing is COMPLETE.**

6. **Phase 4 exit-criterion** (separate workstream, not analytics): importer trigger
   + end-to-end parity test; LoggingSession write leftovers (`mergeSessions`,
   `+Continuity`, repair loop). See the
   [phase 4 cutover status](2026-06-20-phase4-cutover-status.md).

**Resolved design decisions:** the `BragSheetStatValue` union crosses the FFI as **flat
records** (per surface), not a tagged union; furthest-contact records compute **in SQL**
(UDF + `ORDER BY`/window), not Rust-side folds.

# Rust-core / cross-platform migration — START HERE

**Living status + single continuation point** for the Rust-core migration (the work
that makes Carrier Wave's logic portable across iOS / macOS / Android via UniFFI).
This is the canonical "where are we, what's next" doc — the dated design/handoff docs
are the detail; **this is the index.** Update it when phase status changes.

Last updated: **2026-06-28** — **macOS CW Sweep cw-store foundation landed** (mirror trio
hoisted into the `CarrierWaveData` package; CW Sweep runs the mirror + seed importer +
reconciler in shadow mode, no-op by default; both apps build clean). Also fixed a hidden RBN
facade-cutover straggler that left CW Sweep non-compiling, and corrected the "Sweep xcodebuild
deadlock" misdiagnosis (it's slow cold SPM resolution). See the Cross-platform reach section +
step 10. Prior — **2026-06-27: Phase 4 on-device validation gate CLEARED.** The
consumer-snapshot unwind (`logQSO` returns a `Sendable` `LoggedQSO`, commit `adb3d27d`)
landed, and the full on-device sweep passed on `theseus`: shadow QSO-count parity + saved-query
parity sweep with **no mismatches**, a full session lifecycle (create → log → mark uploads →
record spots → merge → end → delete) clean in the write log, and the `.on` smoke test green
across Dashboard / Awards / map / Brag. iOS Phase 4 reads+writes+analytics are validated under
`.on` against real data. **`.on` is NOT yet the production default** — that stays gated on
Phase 5 (server `cw-sync` must own deletes before SwiftData can stop being the CloudKit replica).

Prior (2026-06-21): off-main write-seam cutover + follower-completeness reconcile. Per-context
mirror suppression + a `nonisolated` `OffMainStoreSeam` + a `BatchedRewrite` commit hook route
all background writers canonically; `CwStoreReconciler` prunes orphan rows the mirror can't see.

## ⇒ Handoff — next session starts here

**Just finished (this session):** the **off-main write-seam cutover** — resolved the real
design blocker. New mechanism:
- **Per-context seam suppression** (`CwStoreMirror.seamWriteDepth` is now
  `[ObjectIdentifier: Int]` keyed by the saving `ModelContext`). The old process-global
  counter was only safe because routed saves were main-actor-serialized; keying by context
  lets a background seam save suppress *only its own* save, never a concurrent main-context
  one. `beginSeamWrite(for:)`/`endSeamWrite(for:)` take a context; all sinks updated.
- **`OffMainStoreSeam`** (new, `Services/RustStore/`) — `nonisolated` off-main analogue of
  `SeamWriteBatch` (set-once `(store, mirror)` handle, `commit(in:storeOps:)` + typed
  helpers for presence / activation-metadata / QSO+presence). Activated in `applyQSOMirrorMode`.
- **`BatchedRewrite` commit hook** — optional `commit:` closure (package change) + collects
  mutated rows, so app-target repairs route their off-main save through `OffMainStoreSeam`
  without the package importing the seam. Covered by `BatchedRewriteTests`.

**Routed (cw-store canonical in `.on`):**
- *Main-actor (existing sinks):* SessionSpot `recordSpots`, WebSDRRecording create/finalize,
  ActivationMetadata (Conditions / WPM-from-spots / LoFi import), LoggingSession unwind
  remainder — `deleteSessionShell`, `+Continuity` (`applyLANSnapshot`/`adopt`), and
  `mergeSessions` (its three shared saves via `SeamWriteBatch`).
- *Off-main (`OffMainStoreSeam`):* `POTAPresenceRepairService`, `HuntingParkRefRepairService`,
  `WPMBackfillService`, and `QSOProcessingActor`'s three ServicePresence-co-mutating saves
  (merge batch loop, `reconcileQRZPresence`, dead-state repair).
- **Two pre-existing latent `.on` divergences fixed in passing:** the average-WPM
  `ActivationMetadata` now rides `endSession`'s coordinated `SeamWriteBatch`
  (`SessionSplitChanges.metadata`); the LoFi-import metadata is routed *before* QSO
  insertion so a later suppressed QSO-chunk save can't swallow it.

**Intentionally left mirror-followed (safe; NOT a gap):** the SyncService sync-upload
marking saves (generic "save-whatever's-dirty" calls deep in the upload pipeline — same call
the existing `commitImportedQSOs` comment defers) and the broader `QSOProcessingActor` repair
fleet (`OrphanRepair`/`POTAGapRepair`/`DataRepairs`/`SessionGrouping`/`POTAReconcile`/
`applyQRZConfirmations`). These are QSO-structural / Phase-5-sync scope, not the named non-QSO
sites. The mirror follows them, so `.on` reads stay correct; per-context suppression means a
routed background save never suppresses one of these followers.

**Verified:** `xc build` green (68s); `xc deploy` → installed + launched on `theseus` with no
new crash (existing crash logs are all 6/20, pre-change); `cargo`-free package loop green
(`BatchedRewriteTests` incl. the new commit-hook test, `EndToEndImportParityTests`);
swiftformat + swiftlint clean. **NOT yet done:** the interactive on-device shadow-mode parity
sweep (flip the flag → run the ExperimentsView parity/sweep buttons → exercise a full session
lifecycle → watch `CwStoreWriteLog` for divergence). That's a UI-driven step; see step 2 below.

**Follower-completeness reconcile (this session, after the shadow sweep failed).** The shadow
parity check exposed a **pre-existing** divergence — cw-store ran +46 QSOs ahead of SwiftData.
Root cause: the mirror only sees per-object `context.delete` (via `deletedModelsArray`); it is
**blind to** bulk `modelContext.delete(model:)` (no per-object notification), **CloudKit remote
deletes** (merged via the store coordinator, not a `save()`), and the importer is upsert-only
(never prunes). So deleted rows linger in cw-store forever. Fix = a **surgical orphan prune**
(`CwStoreReconciler`, package): snapshot cw-store keys, delete any SwiftData no longer has
(cw-store-keys-first ordering so a concurrent insert is never mis-pruned; reference tables like
`pota_park` untouched; existing FFI only, no Rust regen). Triggers: mirror setup (every launch),
**app foreground** right after `fetchChangesFromCloud` (catches CloudKit remote deletes), a
manual "Reconcile cw-store" button, and `clearAllQSOs` (immediate prune after the bulk delete).
3 package tests incl. the bulk-delete-all case. **Verified on `theseus`: parity now reads OK.**

> This is why count-parity could never hold on the mirror alone — the CloudKit-remote-delete
> blind spot is *structural* to the follower, the same reason SwiftData stays canonical until
> **Phase 5** (server `cw-sync` becomes the delete source of truth). The reconcile makes the
> follower self-heal in the interim.

Latest `main` commit before this session: `8d7c6257`. **All changes are uncommitted.**

**Next:**
1. **On-device shadow sweep** — ✅ **DONE (2026-06-27).** Full lifecycle clean, parity green,
   `.on` smoke green. See the header.
2. **Importer trigger + e2e parity test** — ✅ done (see git log / phase4 doc).
3. **macOS Sweep cw-store seam** (step 10 below) — ✅ **foundation landed (2026-06-28).**
   The "Sweep xcodebuild deadlock" that blocked this was a **misdiagnosis** — it's slow cold
   SwiftPM package resolution, not a hang (give the first cold build ~6 min; incrementals are
   ~30s). The first real Sweep build surfaced + fixed a hidden RBN cutover straggler
   (`Services/Spots/RBNClient.swift` still used deleted response wrappers). Then the cw-store
   **mirror foundation** was wired into CW Sweep: the mirror trio was hoisted into the
   `CarrierWaveData` package (shared by both apps; iOS still builds clean), and
   `CWSweepApp+CwStore.swift` starts the mirror + seed importer + reconciler in shadow mode
   (no-op when `cwStoreQSOMode == .off`). **Next for Sweep:** hoist the write-sink seams and
   route Sweep's write sites + read/analytics overlays for `.on` (step 10).

**Do NOT** touch server/auth/Phase-5 files on `main` — they live on the
`phase5-oauth-foundation` worktree (separate instance).

## Master references (read for detail, not status)

| Area | Doc |
|------|-----|
| Overall migration plan (phases 0–6, architecture, FFI strategy) | [2026-06-13-rust-core-migration.md](2026-06-13-rust-core-migration.md) |
| Phase 4 cutover status (per-entity + analytics) | [2026-06-20-phase4-cutover-status.md](2026-06-20-phase4-cutover-status.md) |
| Analytics surface design (first cut N0–N6) | [2026-06-20-rust-analytics-surface-design.md](2026-06-20-rust-analytics-surface-design.md) |
| Analytics comprehensiveness audit (gap-closing follow-on) | [2026-06-21-analytics-models-comprehensiveness-audit.md](2026-06-21-analytics-models-comprehensiveness-audit.md) |
| Data fidelity audit (schema) | [2026-06-14-cw-store-fidelity-audit.md](2026-06-14-cw-store-fidelity-audit.md) |
| Finish handoff (Phases 4–6 recipe) | [2026-06-18-rustification-finish-handoff.md](2026-06-18-rustification-finish-handoff.md) |
| LoggingSession write unwind | [2026-06-20-loggingsession-write-unwind.md](2026-06-20-loggingsession-write-unwind.md) |

## Phase status

| Phase | Scope | State |
|-------|-------|-------|
| 0–3 | Toolchain, FT8, domain logic, net clients | ✅ DONE (Rust side) |
| **4** | **Persistence: SwiftData → cw-store** | ✅ **iOS validated** — analytics, importer + e2e parity, off-main write-seam cutover, consumer-snapshot unwind, **and the on-device shadow + `.on` sweep (2026-06-27)** all DONE. Structural remainder (`import SwiftData` → 0; `.on` as default) is **Phase-5-gated** (SwiftData stays the CloudKit replica until `cw-sync` owns deletes). macOS Sweep seam (step 10) is the open iOS-side-mature item. |
| 5 | Sync (CloudKit → server) + OAuth2 auth | 🔄 in flight — **separate worktree**, see below |
| 6 | Android second consumer | 🧪 spiked (Compose + Kotlin/cargo-ndk); full parity awaits 4–5 |

## In-flight work (who's where — two concurrent streams)

- **Analytics (Phase 4) → branch `main`.** QSO reads+writes cut over; all 12 entities
  mirror + delete FFI; **analytics read-sources complete and routing largely done** —
  StatsComputationActor (counts + `wasData`), GridOverlay, MyParks, EquipmentStats,
  **EquipmentItemDetail**, ServicePresence, POTAAwards all overlay cw-store under `.on`.
  `pota_park` table (schema **v4**) + `pota_awards`/`was250`/`was_drilldown`/
  `session_item_detail`/`brag_distance_stats`/`brag_streaks`/`brag_geographic`/`brag_records`/
  `brag_session_stats`/`brag_pota`/`brag_average_rst`/`worked_member_callsigns` aggregates added
  beyond the N0–N6 first cut, plus the `cw_grid_distance_km`/`cw_continent`/`cw_mode_canonical`/
  `cw_rst_s` SQLite UDFs (beside `cw_lower`/`cw_mode_family`) and the `cw_domain::continent`
  port. **All analytics consumers are now routed** — `BragSheetComputationActor` (the last
  one) overlays cw-store under `.on` via `+RustOverlay`, with the brag period passed as a
  `ParsedQuery.date_window` (UTC instant range the DSL can't express). Dormant until
  `CwStoreQSOMode == .on` on-device.
- **OAuth2 / Phase 5 → worktree `.claude/worktrees/phase5-oauth-foundation`**
  (branch `server/phase5-oauth-foundation`). A separate Claude instance is building the
  Phase 5 auth overhaul + sync there. **Do not edit server/auth files or Phase 5 docs on
  `main`** — they live on that branch. (It has its own committed edit to
  phase4-cutover-status.md; expect a trivial 3-line merge there.)

## Cross-platform reach (important nuance)

The aggregates and tables added on `main` live in **cw-store + cw-ffi**, so they reach
**Android for free** once `android/build-rust.sh` regenerates the Kotlin bindings (same
as the entity-delete FFI). What is **iOS-only**: the Swift `AnalyticsAggregator` oracle,
the parity tests, and the `.on` routing.

**macOS (CW Sweep) — foundation landed (2026-06-28).** The cw-store **mirror seam now
runs in CW Sweep** in shadow mode. To share one implementation, the mirror trio
(`CwStoreMirror` + `CwStoreMirrorActor` + `CwStoreWriteLog`, plus `CwStoreMirrorRegistry`)
was **hoisted out of the iOS app target into the `CarrierWaveData` package** (made
`public`, `import UIKit` → `Foundation`); the iOS app re-resolves them from the package
and still builds clean (64s). CW Sweep's `CWSweepApp+CwStore.swift` mirrors the iOS
`applyQSOMirrorMode` foundation: start the mirror, run the one-time seed importer
(`CwStoreImportCoordinator.appGroup`), and reconcile orphans — all **no-op when
`CwStoreQSOMode == .off`** (the default; CW Sweep has no Experiments UI, so the mode is
driven purely by the `cwStoreQSOMode` `UserDefaults` key). Each app mirrors its own local
CloudKit-synced SwiftData replica into its own per-device app-group `cw-store.db`.
**Still iOS-only (NOT yet in Sweep):** the write-sink `.on` routing (QSOWriteSink /
EntityWriteSink / SeamWriteBatch / OffMainStoreSeam), the read-source cutover, and the
analytics `.on` overlays — those are the next Sweep increments (see step 10).

## Next steps — single ordered list

**Analytics (Phase 4's aggregation surface) — ✅ ALL DONE (history below; nothing left here):**
1. ✅ **EquipmentItemDetail** — `session_item_detail` aggregate (per-item band/mode/
   distance breakdown) landed + routed under `.on`; parity tests green. This slice also
   landed the `cw_grid_distance_km` UDF and aligned the `.off` path on the shared
   haversine (`MaidenheadConverter.distanceKm`, replacing `CLLocation` — sub-0.5 % shift).
2. ✅ **Brag distance metrics** — `brag_distance_stats(query)` landed: furthest overall/
   QRP/CW/CW-QRP/perfect-RST + per-band + average + lowest-power + best-watts-per-mile, all
   bounded SQL over the `cw_grid_distance_km` UDF (ORDER BY/LIMIT/window — no row loading).
   FFI returns a **flat `FfiBragDistanceStats`** record the Swift side maps (resolved the
   FFI-representation design call: flat record, not a tagged union). Parity green
   (`AnalyticsBragDistanceParityTests`). **Not yet routed** — that's step 5.
3. ✅ **Brag streaks** — `brag_streaks(query, today)` landed: on-air + per-mode (CW/Phone/
   Digital) + activation (≥10-unique-QSO park days) day streaks. Distinct active days come
   from SQL (`strftime` — bounded by day count), folded via `cw_domain::streak`. **Decision:
   normalized on-air day-bucketing local→UTC** (Swift used `Calendar.current`; now consistent
   with every other brag day-stat + DST-correct). `today` is passed in (cw-store can't read
   the clock); FFI takes a `YYYY-MM-DD` string. Parity green (`AnalyticsBragStreaksParityTests`).
   **Peak-rate windows were not part of the actor's catalog** — no such stat exists; the
   streak set is complete. Not routed (step 5).
4. ✅ **Brag new-this-period + geographic rollups** — `brag_geographic(query)` landed: DXCC
   entities, new-this-period (all-time-earliest vs period-start), states/provinces, grid
   squares, continents, most-continents-in-a-day, WAS progress. Ported the `ContinentMapper`
   sets verbatim into **`cw_domain::continent`** + a `cw_continent(dxcc)` SQL UDF. Parity
   green (`AnalyticsBragGeographicParityTests`). **The full Brag stat catalog (totals,
   distance, streaks, geographic) is now in Rust.** Not routed (step 5).
5. **Route `BragSheetComputationActor`** onto the above under `.on` (last unrouted
   consumer). **Correction to the original audit:** steps 2–4 did NOT cover the full brag
   catalog — the actor has 11 stat categories (~58 stats). Porting the remainder before
   routing:
   - ✅ **Records/volume/fun (SQL-shaped)** — `brag_records(query)` landed: most-QSOs-in-a-
     day/session, most countries/bands per day, busiest band/mode, most-active weekday,
     repeat customer, earliest/latest QSO, total distance, active modes. Added the
     `cw_mode_canonical` UDF. Parity green (`AnalyticsBragRecordsParityTests`).
   - ✅ **Session-sequence stats** — `brag_session_stats(query)` landed: operating hours,
     fastest-10, best-session-rate, fastest-activation, longest-session, peak-15-min-rate,
     largest-Nfer. Fetch-and-fold (minimal columns: session key, timestamp, park, UTC day →
     folded in Rust, O(period rows)), the first non-`GROUP BY` aggregate. Parity green
     (`AnalyticsBragSessionParityTests`).
   - ✅ **POTA-brag** — `brag_pota(query)` landed: parks activated / hunted / P2P /
     best-activation / new-parks (largest-Nfer was in session-stats). Parity green
     (`AnalyticsBragPotaParityTests`).
   - ✅ **Misc + club** — `brag_average_rst(query)` (via a `cw_rst_s` UDF) +
     `worked_member_callsigns(query, members)` (the **parameterized aggregate** — the app
     passes the club member-callsign list in; the club→callsign mapping stays app-side, so
     `clubMembersWorked` = list count and `clubsRepresented` maps the list to clubs app-side).
     `fastestCWSpeed` is a `.noData` stub in the actor — nothing to port. Parity green
     (`AnalyticsBragSignalParityTests`). *(Last two slices ported in parallel worktree
     subagents, then merged + bindings regenerated on `main`.)*

   - ✅ **ROUTED** — `BragSheetComputationActor.computeFromStore` (`+RustOverlay`) overlays
     cw-store under `.on`, mapping every `BragSheetStatType` to its aggregate value (the
     `.off` snapshot scan is skipped entirely). **Period as window, not DSL:** the brag period
     is a UTC instant range `[start, now]` the day-granular DSL can't express, so a
     `date_window: (Option<i64>, Option<i64>)` field was added to `ParsedQuery` —
     `compile_where` ANDs it onto every brag aggregate's period filter (and the `new_dxcc`/
     `new_parks` all-time subqueries, which don't use the compiled where, stay correctly
     unwindowed). The 9 brag FFI methods gained `start/end: Option<i64>`; the Swift read-source
     methods default them to `nil` so existing call sites/parity tests are unchanged. Also
     aligned the `.off` path: `BragSheetQSOSnapshot.distanceKm` → `MaidenheadConverter.distanceKm`
     (haversine, was `CLLocation`) and the on-air streak day-bucketing → UTC, so `.on`/`.off`/
     oracle agree. Dormant until `CwStoreQSOMode == .on` on-device.

   **The entire Brag stat catalog is ported AND routed.** `BragSheetComputationActor` is the
   last analytics consumer; with it on `.on`, the brag full-log SwiftData scan is retired.

**Phase 4 exit (separate from analytics):**
6. **Remaining non-QSO entity write sites** — ✅ **DONE (off-main write-seam cutover, 2026-06-21).**
   The `@MainActor` design blocker is resolved: **per-context** mirror suppression (so a
   background seam save can't suppress a concurrent main-context save) + a `nonisolated`
   `OffMainStoreSeam` (off-main analogue of `SeamWriteBatch`) + a `BatchedRewrite` `commit:`
   hook. All named sites routed canonically — SessionSpot, WebSDRRecording, ActivationMetadata,
   standalone ServicePresence (`POTAPresenceRepairService` + `QSOProcessingActor`'s three
   presence-co-mutating saves), and the LoggingSession unwind remainder
   (`mergeSessions`/`deleteSessionShell`/`+Continuity`). Two pre-existing latent `.on`
   divergences fixed (endSession WPM metadata; LoFi-import metadata). Builds + deploys; package
   loop green. **Gate:** the interactive on-device shadow-parity sweep (handoff step 1) — not
   yet run. **Deliberately left mirror-followed** (safe followers, Phase-5/QSO-cutover scope):
   the SyncService upload-marking saves + the `QSOProcessingActor` repair fleet
   (Orphan/POTAGap/DataRepairs/SessionGrouping/POTAReconcile/applyQRZConfirmations).
7. **Importer trigger + end-to-end parity test** — ✅ **DONE.** Trigger was already wired
   (`CwStoreImportCoordinator.runIfNeeded`, idempotent via `cwStoreImportCompletedVersion`,
   fired automatically on `.off → .shadow/.on` in `applyQSOMirrorMode` + manually via the
   `CwStoreMigrationRow` button). End-to-end parity test landed this session
   (`EndToEndImportParityTests` — importAll batched path → read-source seam parity, package
   loop). **Still gated on the on-device validation loop** (next step 2 in the handoff): the
   seed import + routed reads have never run on a device against real data. Realistic Phase 4
   exit is "all reads+writes on cw-store, SwiftData demoted to the CloudKit/sync replica," not
   zero `import SwiftData` (literal deletion is Phase 5).

**Phases 5–6 (other streams):**
8. **Phase 5** — OAuth2 overhaul + server `cw-sync` transport (replaces CloudKit). In
   flight on the worktree branch; gates SwiftData retirement and Android.
9. **Phase 6** — Android full parity (after 4–5); regenerate Kotlin bindings to pick up
   the new FFI (pota_park, pota_awards, was250, was_drilldown, deletes).
10. **macOS Sweep** — ✅ **foundation landed (2026-06-28):** mirror seam (hoisted to the
    package) + seed importer + reconciler run in CW Sweep in shadow mode, no-op by default.
    **Remaining (the lockstep application):** hoist the write-sink seams
    (QSOWriteSink / ServicePresenceWriteSink / EntityWriteSink(+Factory) / SeamWriteBatch /
    OffMainStoreSeam) to the package the same way, route CW Sweep's write sites through them
    for `.on`, then apply the read-source + analytics `.on` overlays. Verify with a
    shadow-mode parity sweep on Sweep mirroring the iOS 2026-06-27 gate.

## The add-a-slice recipe (every analytics aggregate)

cw-store struct + SQL/fold + Rust tests → cw-ffi DTO + method → `build-xcframework.sh`
regen (commit `CwFfi+Generated.swift`) → CarrierWaveData result type +
`RustAnalyticsReadSource` method + `AnalyticsAggregator` oracle (independent
re-derivation) + `Analytics*ParityTests` (`Rust == oracle`) → route the consuming actor
with an `.on` overlay + SwiftData fallback. Verify: `cargo test --workspace` + clippy
`-D warnings`; `swift test` parity; iOS `xcodebuild` build; swiftformat + swiftlint.

# Brag Sheet → Rust + Android port (replace Swift)

**Date:** 2026-07-11
**Status:** Design approved, pending spec review
**Related:** `feedback_rust_swift_parity`, `project_android_ios_tab_parity`, `project_sessions_hunterlog_rust`

## Goal

Move the Brag Sheet feature's domain model, configuration, and compute-orchestration
into shared Rust (consumed by iOS + Android via UniFFI), delete the duplicate Swift
computation, and build the Android brag sheet on the shared layer. Full behavioral
parity across all 58 stats is the acceptance bar.

## What a brag sheet is

A personalized statistics dashboard: it aggregates a radio operator's achievements
(QSO counts, distance records, streaks, POTA activations, etc.) across three time
windows (weekly / monthly / all-time). The user customizes which stats appear (58
metrics across 11 categories) and promotes up to 4 per period as large "hero" cards.
Results are also used by shareable activation cards (rendering stays in Swift).

## Current state (important — the feature is already half-ported)

**Already in Rust + exposed via FFI** (`cw-store/analytics.rs`, `cw-ffi/lib.rs`):
The heavy stat *computation* was ported incrementally over ~10 commits —
`brag_distance_stats`, `brag_streaks`, `brag_records`, `brag_session_stats`,
`brag_geographic`, `brag_pota`, `brag_period_metrics`, `brag_average_rst`, plus the
`FfiBrag*` record types. iOS already routes to these via
`BragSheetComputationActor+RustOverlay.swift` when the store is `.on`, with a
**duplicate ~1,700-line Swift snapshot computation** as a fallback.

**Still Swift-only:**
- Catalog/config domain model: `BragSheetStatType` (58), `BragSheetCategory` (11),
  `BragSheetPeriod`, `BragSheetPreset` (7), `BragSheetConfiguration`/`PeriodConfig`,
  `BragSheetStatValue`.
- Orchestration: `AsyncBragSheetStats` maps a config → which FFI stats to fetch →
  assembled `[StatType: StatValue]`.
- Config persistence: local `UserDefaults` JSON (`"bragSheetConfiguration"`).
- The Swift fallback compute (`BragSheetComputationActor` + 4 extensions) duplicating
  the Rust path.

**Android:** none of this — only calls `bragStreaks` once in `HomeViewModel`.

## Scope

### In scope
1. Shared Rust catalog/config model (`cw-domain/brag_sheet.rs`).
2. A compute-orchestration entry in `cw-store` that runs a config's enabled stats via
   the existing `brag_*` aggregates.
3. A `BragSheetApi` FFI facade (mirrors `SessionWizardApi`): catalog, presets, config
   CRUD, `compute_brag`.
4. Config moved to cw-store `kv` (shared single source of truth; per-device local —
   `sync_kv` does not cross-device sync), with one-time iOS migration from UserDefaults.
5. iOS: swap `AsyncBragSheetStats` onto `BragSheetApi`; delete the Swift compute +
   domain enums + overlay + snapshot.
6. Android: net-new brag sheet screen + customize screen + ViewModel on the shared FFI.
7. Full 58-stat parity.

### Out of scope
Share-card **rendering** — `BragSheetShareRenderer`, map renderers,
`SessionBragSheetCard`, `TOTABragSheet*`, and `BragSheetSource` — stays in the Swift
view layer. Android may add its own share cards later. `BragSheetSource` is an
activation-share data wrapper, not core brag-sheet logic.

## Architecture

Three shared-Rust pieces:

### 1. `cw-domain/brag_sheet.rs` (new, pure, unit-tested)
- `BragStatType` — 58-case enum (full list below).
- `BragCategory` — 11-case enum; each stat maps to a category.
- `BragPeriod` — `Weekly` (Monday 0000Z→now), `Monthly` (1st 0000Z→now),
  `AllTime` (past→now). **UTC calendar throughout.** Provides `[start, end]` unix-second
  window given "now".
- `BragPreset` — 7 curated configs: `General`, `Dxer`, `Qrp`, `Activator`, `Contester`,
  `CwEnthusiast`, `ShowEverything`. Each has an ordered enabled-stat list; default hero
  stats = first 4.
- `BragStatValue` — display enum (variants below).
- `BragPeriodConfig` — `enabled_stats: Vec<BragStatType>`, `hero_stats: Vec<BragStatType>`
  (max 4), `base_preset: Option<BragPreset>`; `toggle`, `toggle_hero`, `move`, `from_preset`.
- `BragConfiguration` — `weekly`/`monthly`/`all_time: BragPeriodConfig`, `include_map`,
  `include_equipment_summary`, `gold_record_badges`; accessors + `apply_preset` +
  `copy_config`. serde-serializable (JSON persisted in kv).
- Per-stat metadata: `display_name`, `short_display_name`, `category`, `icon_key`
  (semantic — see Formatting).

### 2. `cw-store/analytics.rs` (exists) — orchestration helper
Add one function: given a `BragPeriod` window + a config's enabled-stat list, run the
relevant existing `brag_*` aggregates and return `Vec<(BragStatType, BragStatValue)>`.
This replaces `AsyncBragSheetStats`'s per-stat Swift dispatch. Reuses existing
aggregates; no new SQL per stat unless a currently-Swift-only stat lacks a Rust
aggregate (audit during Phase 2 — the RustOverlay coverage tells us which).

### 3. `cw-ffi/brag_sheet_api.rs` (new facade)
`BragSheetApi { store: Arc<FieldStore> }`, `#[uniffi::export]`:
- `catalog() -> Vec<FfiBragStatMeta>` — all 58 with display name / short name / category /
  icon key.
- `categories() -> Vec<FfiBragCategoryMeta>`.
- `presets() -> Vec<FfiBragPreset>`.
- `load_config() -> FfiBragConfiguration` (from kv; defaults if absent).
- `save_config(FfiBragConfiguration)`.
- `compute_brag(period) -> Vec<FfiBragStatResult>` where `FfiBragStatResult { stat_type,
  value (structured), formatted (canonical display string), icon_key }`.

## Data flow

```
config (cw-store kv) ──▶ BragSheetApi.compute_brag(period)
                          ├─ resolve [start,end] window (UTC)
                          ├─ run enabled stats via existing brag_* aggregates
                          └─ map → Vec<FfiBragStatResult>{type, value, formatted, icon}
                                          │
                          platform view layer renders (SwiftUI / Compose)
```

## Config persistence & migration

- Stored in the shared `synced_config` table (config_type `"bragSheet"`) as JSON — single
  source of truth. iOS migrates the legacy `UserDefaults` blob in via `import_legacy_config`.
- **Cross-device sync is groundwork-only and gated OFF.** `synced_config` is wired as a
  first-class synced entity (dirty/push/pull, LWW on `modified_at`) and the pull path now
  tolerantly skips unknown ops, but `CONFIG_SYNC_PUSH_ENABLED = false` in
  `cw-ffi/sync_transport.rs` — no config op reaches the wire. This is deliberate: pushing a
  new op type to a peer still on the currently-released (non-tolerant) client would abort
  that peer's whole pull batch (QSOs included). Flip the flag to `true` only in a release
  AFTER the tolerant-decoder client is the floor version across all devices.
- `BragSheetApi` owns load/mutate/save.
- **One-time iOS migration:** on first run after update, if
  `UserDefaults["bragSheetConfiguration"]` exists and the kv key is empty, decode the old
  blob, write it to kv, and stop reading UserDefaults. Preserves existing users'
  customizations.

## StatValue formatting & icons

- **Formatting → Rust (max parity).** `compute_brag` returns each result both as
  structured data (`FfiBrag*` records already exist) and as a canonical display string
  (`"0312Z"`, `"38/50"`, distance, rate). iOS and Android render byte-identical text.
  `BragSheetStatRendering.swift` shrinks to pure view composition.
- **Icons → semantic keys.** Rust exposes an `icon_key` per stat (e.g. `distance`,
  `streak`, `pota`); iOS maps key→SF Symbol, Android maps key→Material icon. SF-Symbol
  name strings are **not** put in Rust (they don't port to Android).

## BragStatValue variants (mirror of Swift)

`Count(i64)`, `Distance{km}`, `Duration{seconds}`, `Rate{value, label}`,
`Contact{callsign, distance_km?, band?}`, `Power{watts, callsign, distance_km?, band?}`,
`Efficiency{watts_per_mile, detail}`, `Progress{current, total}`,
`Streak{current, longest}`, `BandTable(Vec<BandTableEntry>)`, `DayOfWeek{day, count}`,
`CallsignCount{callsign, count}`, `TimeOfDay{unix_seconds}`,
`ParkDetail{park, date?, count}`, `ModeStreakList(Vec<ModeStreakEntry>)`, `Wpm(i64)`,
`Rst{value, detail?}`, `NoData`.
Supporting: `BandTableEntry{band, callsign, distance_km}`,
`ModeStreakEntry{mode, current, longest}`.

## The 58 stats (catalog, grouped by category)

- **Totals (12):** totalQSOs, totalCWQSOs, totalPhoneQSOs, totalDigitalQSOs,
  totalDistance, operatingDays, operatingHours, activeBands, activeModes,
  uniqueCallsigns, qrpQSOCount, milliwattQSOCount
- **Speed & Rate (4):** fastest10QSOs, peak15MinRate, bestSessionRate, fastestActivation
- **Distance (4):** furthestContact, furthestContactPerBand, furthestQRPContact,
  averageContactDistance
- **Power & Efficiency (2):** lowestPowerContact, bestWattsPerMile
- **Geographic Reach (7):** dxccEntities, newDXCCEntities, statesAndProvinces,
  gridSquares, continents, mostContinentsInADay, workedAllStatesProgress
- **Volume Records (4):** mostQSOsInADay, mostQSOsInASession, mostCountriesInADay,
  mostBandsInADay
- **Streaks (4):** currentOnAirStreak, bestOnAirStreak, currentActivationStreak,
  modeStreaks
- **POTA (6):** parksActivated, parksHunted, parkToParkContacts, largestNfer,
  bestActivation, newParks
- **CW (3):** fastestCWSpeed, cwDistanceRecord, cwQRPRecord
- **Signal Quality (3):** perfectReports, averageRSTReceived, bestRSTAtDistance
- **Fun & Unique (9):** earliestQSOOfTheDay, latestQSOOfTheDay, longestSession,
  mostActiveDayOfWeek, busiestBand, busiestMode, repeatCustomers, clubMembersWorked,
  clubsRepresented

## iOS changes

- `AsyncBragSheetStats` → thin `@Observable` wrapper over `BragSheetApi`.
- **Delete:** `BragSheetComputationActor` + 4 extensions + `+RustOverlay`,
  `BragSheetSnapshot`, and domain enums (`BragSheetStatType/Category/Period/Preset/
  Configuration/StatValue`) — replaced by FFI types.
- **Keep:** all SwiftUI views (`BragSheetView`, `BragSheetCustomizeView`, dashboard
  cards) and share-card rendering. `BragSheetStatRendering.swift` reduced to view
  composition over the shared formatted strings.
- App-target wrapper-shadow check (`feedback_quick_entry_app_wrapper_shadow`): confirm no
  app-target enum shadows the Core type.

## Android changes (net-new)

- Brag sheet screen + customize screen + `ViewModel` consuming `BragSheetApi`, mirroring
  iOS feature parity (`project_android_ios_tab_parity`).
- Icon key → Material icon mapping table.
- Wrap store-touching FFI calls in `withContext(Dispatchers.IO)`
  (`feedback_uniffi_async_dispatcher`).

## Testing / parity bar

- Rust unit tests: catalog completeness (all 58 present, each has metadata + category),
  config mutation (`toggle`, `toggle_hero` max-4, `move`, `apply_preset`), period
  windowing (UTC boundaries), formatting (canonical strings per variant).
- **Golden parity test:** before deleting the Swift compute, snapshot current iOS output
  for a fixture log across all three periods and all 58 stats; assert Rust `compute_brag`
  produces matching structured values + formatted strings. This guards the swap. Run the
  `#filePath`-fixture test on the Simulator, not device (`feedback_test_harness_device_vs_sim`).

## Phasing

Each phase independently buildable.

1. **Rust model** — `cw-domain/brag_sheet.rs` (catalog + config + presets + StatValue);
   FFI types; config CRUD via kv. Rust unit tests.
2. **Compute orchestration** — `compute_brag` entry + FFI. Audit RustOverlay coverage for
   any stat lacking a Rust aggregate; add if needed. Golden parity vs Swift for fixture.
3. **iOS swap** — route `AsyncBragSheetStats` through `BragSheetApi`; migrate config from
   UserDefaults; delete Swift compute + enums + overlay + snapshot. Build + device verify.
4. **Android UI** — new brag sheet + customize screens on shared FFI.
5. **Cleanup** — `FILE_INDEX.md` updates (iOS services/views + Rust), `CHANGELOG.md`,
   What's New if a version bumps, regen xcframework (`build-xcframework.sh`) + Kotlin
   bindings.

## Risks / open questions

- **Stat coverage gap:** if a currently-Swift-only stat has no Rust aggregate yet
  (RustOverlay may fall back for some), Phase 2 must add it. Audit early.
- **Distance parity:** Rust must match the `cw_grid_distance_km` UDF / haversine used by
  the Swift path exactly.
- **Streak day-bucketing:** Rust uses UTC calendar days; verify no device-local drift vs
  the old Swift path.
- **kv sync semantics [RESOLVED]:** `sync_kv` is per-device local and does NOT participate
  in E2E sync — brag config stays per-device. If cross-device config sync is desired, move
  the blob to a synced entity. Original note below.
- **kv sync semantics:** confirm `sync_kv` participates in E2E sync as expected, or gate
  brag config out of sync until intended.

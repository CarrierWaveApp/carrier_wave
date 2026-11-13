# Brag Sheet Rust + Android Port — Implementation Plan

> **For agentic workers:** Implement task-by-task. Steps use checkbox (`- [ ]`) syntax.
> Each task ends with a build/test gate. The Swift sources named in each task are the
> **authoritative port reference** — read them and port faithfully (this is a port, not
> greenfield; matching existing behavior byte-for-byte is the bar).

**Goal:** Move the Brag Sheet catalog/config model + compute-orchestration into shared
Rust (`BragSheetApi`), delete the duplicate Swift computation, and build the Android brag
sheet on the shared layer — full 58-stat parity.

**Architecture:** New pure `cw-domain/brag_sheet.rs` (catalog + config + presets +
StatValue); a compute-orchestration helper in `cw-store/analytics.rs` reusing the existing
`brag_*` aggregates; a `BragSheetApi` FFI facade (mirrors `SessionWizardApi`) exposing
catalog/presets/config-CRUD/`compute_brag`. iOS swaps `AsyncBragSheetStats` onto the FFI
and deletes ~1,700 lines of Swift compute + domain enums; Android builds the feature new.

**Tech Stack:** Rust (cw-domain / cw-store / cw-ffi), UniFFI, SwiftUI/SwiftData (iOS),
Kotlin/Compose (Android), SQLCipher via cw-store.

## Global Constraints

- **Rust format:** `rust/cw-core` is hand-formatted — do **NOT** run `cargo fmt`. Gate is
  `cargo build` + `cargo clippy` + `cargo test`.
- **UTC calendar** for all period windowing and day-bucketing (streaks, "per day" stats).
- **Metadata pseudo-modes** (`WEATHER`/`SOLAR`/`NOTE`) never counted — reuse the existing
  cw-store filtering the `brag_*` aggregates already apply.
- **cw-store ids are lowercase**; never compare against Swift `.uuidString` (uppercase).
- **Android:** wrap store-touching FFI in `withContext(Dispatchers.IO)` (ANR risk).
- **Full parity** across all 58 stats is the acceptance bar; the golden parity test
  (Task 9) guards the iOS swap.
- **Do not delete** the Swift compute until the golden parity test passes (Task 9 before
  Task 10).

## Source-of-truth Swift files (the port reference)

| Concern | File |
|---|---|
| 58 stat types + display/short names + category + icon | `swift/ios/CarrierWave/Models/BragSheet/BragSheetStatType.swift` |
| 11 categories + metadata | `.../BragSheet/BragSheetCategory.swift` |
| 3 periods + UTC windows | `.../BragSheet/BragSheetPeriod.swift` |
| 7 presets + ordered stat arrays | `.../BragSheet/BragSheetPreset.swift` |
| StatValue variants + supporting structs | `.../BragSheet/BragSheetStatValue.swift` |
| Configuration/PeriodConfig + persistence | `.../BragSheet/BragSheetConfiguration.swift` |
| stat→FFI-aggregate mapping (the orchestration) | `.../Services/BragSheet/BragSheetComputationActor+RustOverlay.swift` |
| display-string formatting | `.../Views/BragSheet/BragSheetStatRendering.swift` |
| observable wrapper (to become thin) | `.../Views/Dashboard/AsyncBragSheetStats.swift` |

Existing Rust aggregates already available (`cw-store/analytics.rs`, exposed on
`FieldStore` in `cw-ffi/lib.rs`): `brag_distance_stats`, `brag_streaks`, `brag_records`,
`brag_session_stats`, `brag_geographic`, `brag_pota`, `brag_period_metrics`,
`brag_average_rst`, plus `FfiBrag*` records.

## File structure

**Create:**
- `rust/cw-core/cw-domain/src/brag_sheet.rs` — catalog, categories, periods, presets,
  StatValue, Configuration/PeriodConfig (pure, serde, unit-tested).
- `rust/cw-core/cw-ffi/src/brag_sheet_api.rs` — `BragSheetApi` facade + `Ffi*` types +
  canonical formatting.
- `android/app/src/main/java/app/carrierwave/android/ui/brag/BragSheetScreen.kt`,
  `BragSheetCustomizeScreen.kt`, `BragSheetViewModel.kt`.

**Modify:**
- `rust/cw-core/cw-domain/src/lib.rs` — `pub mod brag_sheet;`
- `rust/cw-core/cw-store/src/analytics.rs` — add `compute_configured_brag` orchestration.
- `rust/cw-core/cw-ffi/src/lib.rs` — register `mod brag_sheet_api;` / uniffi export.
- iOS `AsyncBragSheetStats.swift` — thin wrapper over `BragSheetApi`.
- iOS `BragSheetStatRendering.swift` — consume shared formatted strings.
- iOS FILE_INDEX + Rust FILE_INDEX; `CHANGELOG.md`.

**Delete (iOS, after Task 9 passes):**
- `Services/BragSheet/BragSheetComputationActor.swift` + `+Totals/+Distance/+Records/
  +POTA/+RustOverlay` extensions + `BragSheetSnapshot.swift`.
- `Models/BragSheet/BragSheet{StatType,Category,Period,Preset,Configuration,StatValue}.swift`
  (replaced by FFI types via a thin Swift typealias/adapter layer — see Task 10).

---

## PHASE 1 — Rust domain model

### Task 1: `BragStatType` + `BragCategory` enums with metadata

**Files:**
- Create: `rust/cw-core/cw-domain/src/brag_sheet.rs`
- Modify: `rust/cw-core/cw-domain/src/lib.rs` (add `pub mod brag_sheet;`)
- Test: inline `#[cfg(test)]` in `brag_sheet.rs`

**Interfaces — Produces:**
- `enum BragStatType` (58 variants, `#[derive(Clone,Copy,PartialEq,Eq,Hash,Debug,Serialize,Deserialize)]`,
  serde `rename_all = "camelCase"` matching the Swift `rawValue` strings exactly).
- `enum BragCategory` (11 variants: `Totals, SpeedAndRate, Distance, PowerAndEfficiency,
  GeographicReach, VolumeRecords, Streaks, Pota, Cw, SignalQuality, FunAndUnique`).
- `impl BragStatType { fn all() -> Vec<Self>; fn display_name(&self)->&'static str;
  fn short_display_name(&self)->&'static str; fn category(&self)->BragCategory;
  fn icon_key(&self)->&'static str; fn as_str(&self)->&'static str }`
- `impl BragCategory { fn all()->Vec<Self>; fn display_name(&self)->&'static str;
  fn stats(&self)->Vec<BragStatType> }`
- `icon_key` is the semantic key derived from category (matches the Swift
  `systemImage`-by-category switch): totals→`"number"`, speedAndRate→`"gauge"`,
  distance→`"bearing"`, powerAndEfficiency→`"bolt"`, geographicReach→`"globe"`,
  volumeRecords→`"trophy"`, streaks→`"flame"`, pota→`"tree"`, cw→`"waveform"`,
  signalQuality→`"antenna"`, funAndUnique→`"sparkles"`. (Platform UIs map these to
  SF Symbols / Material icons.)

- [ ] **Step 1: Write failing tests** — port from `BragSheetStatType.swift`:
```rust
#[test] fn all_58_stats_present() { assert_eq!(BragStatType::all().len(), 58); }
#[test] fn serde_rawvalue_roundtrip() {
    // camelCase rawValue matches Swift: e.g. TotalQsos -> "totalQSOs"
    assert_eq!(serde_json::to_string(&BragStatType::TotalQsos).unwrap(), "\"totalQSOs\"");
    assert_eq!(BragStatType::FurthestQrpContact.as_str(), "furthestQRPContact");
}
#[test] fn every_stat_has_metadata_and_category() {
    for s in BragStatType::all() {
        assert!(!s.display_name().is_empty());
        assert!(!s.short_display_name().is_empty());
        let _ = s.category();
    }
}
#[test] fn categories_cover_all_stats_partition() {
    let mut seen = 0;
    for c in BragCategory::all() { seen += c.stats().len(); }
    assert_eq!(seen, 58); // each stat in exactly one category
}
```
NOTE: The `QSO`/`QRP`/`DXCC`/`WAS`/`CW`/`RST`/`P2P` acronym casing in rawValues is
load-bearing — serde `rename_all="camelCase"` will NOT produce `totalQSOs` from
`TotalQsos`. Use explicit `#[serde(rename="totalQSOs")]` per-variant where the acronym
casing differs, OR implement `Serialize/Deserialize` via `as_str`/`from_str`. Port the
exact `rawValue` strings from the Swift `case` list (they equal the Swift case names).

- [ ] **Step 2: Run — expect fail** `cd rust/cw-core && cargo test -p cw-domain brag_sheet` → FAIL (module missing)
- [ ] **Step 3: Implement** the two enums + impls, porting all names/categories verbatim
  from `BragSheetStatType.swift` (displayName L110-171, category L173-245,
  shortDisplayName L247-308) and `BragSheetCategory.swift` (displayName + stats mapping).
- [ ] **Step 4: Run — expect pass** `cargo test -p cw-domain brag_sheet`
- [ ] **Step 5: Clippy + commit** `cargo clippy -p cw-domain` then
  `git add -A && git commit -m "cw-domain: BragStatType + BragCategory catalog (58 stats)"`

### Task 2: `BragPeriod` with UTC windows

**Files:** Modify `brag_sheet.rs`; tests inline.

**Interfaces — Produces:**
- `enum BragPeriod { Weekly, Monthly, AllTime }` (serde camelCase: `weekly/monthly/allTime`).
- `impl BragPeriod { fn window(&self, now: chrono::DateTime<Utc>) -> (Option<i64>, Option<i64>) }`
  returning inclusive `(start_unix, end_unix)`; `AllTime` → `(None, Some(now))`.
- `fn default_preset(&self)->BragPreset` (Task 3): weekly→General, monthly→General,
  allTime→ShowEverything (port exact mapping from `BragSheetPeriod.swift` L43-49).

- [ ] **Step 1: Failing tests** (port windows from `BragSheetPeriod.swift` L53-79):
```rust
#[test] fn weekly_starts_monday_0000z() {
    // 2026-07-11 is a Saturday; Monday 00:00Z is 2026-07-06
    let now = Utc.with_ymd_and_hms(2026,7,11,15,0,0).unwrap();
    let (start,_) = BragPeriod::Weekly.window(now);
    assert_eq!(start, Some(Utc.with_ymd_and_hms(2026,7,6,0,0,0).unwrap().timestamp()));
}
#[test] fn monthly_starts_first_0000z() {
    let now = Utc.with_ymd_and_hms(2026,7,11,15,0,0).unwrap();
    let (start,_) = BragPeriod::Monthly.window(now);
    assert_eq!(start, Some(Utc.with_ymd_and_hms(2026,7,1,0,0,0).unwrap().timestamp()));
}
#[test] fn all_time_has_no_start() {
    assert_eq!(BragPeriod::AllTime.window(Utc.with_ymd_and_hms(2026,7,11,0,0,0).unwrap()).0, None);
}
```
- [ ] **Step 2: Run — fail.** `cargo test -p cw-domain brag_sheet::`
- [ ] **Step 3: Implement** using `chrono` (weekday → days-since-Monday; month → day-1).
- [ ] **Step 4: Run — pass.**
- [ ] **Step 5: Commit** `cw-domain: BragPeriod UTC windows`.

### Task 3: `BragPreset` (7 presets, ordered stat arrays)

**Files:** Modify `brag_sheet.rs`.

**Interfaces — Produces:**
- `enum BragPreset { General, Dxer, Qrp, Activator, Contester, CwEnthusiast, ShowEverything }`
  (serde camelCase).
- `impl BragPreset { fn all()->Vec<Self>; fn display_name(&self)->&'static str;
  fn description(&self)->&'static str; fn stats(&self)->Vec<BragStatType>;
  fn default_hero_stats(&self)->Vec<BragStatType> /* first 4 of stats() */ }`

- [ ] **Step 1: Failing tests** (port arrays from `BragSheetPreset.swift` L48-94):
```rust
#[test] fn show_everything_has_all_58() { assert_eq!(BragPreset::ShowEverything.stats().len(), 58); }
#[test] fn default_hero_is_first_four() {
    let p = BragPreset::General;
    assert_eq!(p.default_hero_stats(), p.stats().into_iter().take(4).collect::<Vec<_>>());
}
#[test] fn general_preset_matches_swift() {
    // exact ordered list from BragSheetPreset.swift .general case
    assert_eq!(BragPreset::General.stats(), vec![/* port exact */]);
}
```
- [ ] **Step 2: Run — fail.**
- [ ] **Step 3: Implement**, porting each preset's ordered `stats` array verbatim from
  `BragSheetPreset.swift`; `ShowEverything` = `BragStatType::all()`.
- [ ] **Step 4: Run — pass.**
- [ ] **Step 5: Commit** `cw-domain: BragPreset curated configs`.

### Task 4: `BragConfiguration` + `BragPeriodConfig` (mutation + serde)

**Files:** Modify `brag_sheet.rs`.

**Interfaces — Produces:**
- `struct BragPeriodConfig { enabled_stats: Vec<BragStatType>, hero_stats: Vec<BragStatType>,
  base_preset: Option<BragPreset> }` with `from_preset(BragPreset)`, `toggle(BragStatType)`,
  `toggle_hero(BragStatType)->bool` (max 4; returns success), `move_stat(from:usize,to:usize)`.
- `struct BragConfiguration { weekly, monthly, all_time: BragPeriodConfig, include_map: bool,
  include_equipment_summary: bool, gold_record_badges: bool }` with `Default`,
  `config_for(BragPeriod)->&BragPeriodConfig`, `set_config(BragPeriod, BragPeriodConfig)`,
  `apply_preset(BragPreset, BragPeriod)`, `copy_config(from:BragPeriod,to:BragPeriod)`.
- serde: field names + JSON shape **must match** the existing Swift `Codable` encoding in
  `BragSheetConfiguration.swift` (so the iOS UserDefaults blob migrates cleanly — Task 11).
  Verify the Swift `CodingKeys`/default synthesized names and mirror exactly.

- [ ] **Step 1: Failing tests:**
```rust
#[test] fn toggle_hero_caps_at_four() {
    let mut c = BragPeriodConfig::from_preset(BragPreset::ShowEverything);
    c.hero_stats.clear();
    let stats: Vec<_> = c.enabled_stats.iter().copied().take(5).collect();
    for (i,s) in stats.iter().enumerate() {
        let ok = c.toggle_hero(*s);
        assert_eq!(ok, i < 4); // 5th rejected
    }
    assert_eq!(c.hero_stats.len(), 4);
}
#[test] fn default_config_matches_swift_defaults() { /* weekly/monthly/allTime presets */ }
#[test] fn config_json_roundtrip_matches_swift_blob() {
    // paste a real encoded blob from the Swift Codable output as a fixture string,
    // decode into BragConfiguration, re-encode, assert semantic equality.
}
```
- [ ] **Step 2: Run — fail.**
- [ ] **Step 3: Implement**, porting mutation semantics from `BragSheetConfiguration.swift`
  (toggle L43-50, toggleHero L54-68, move L71-73, accessors L109-134).
- [ ] **Step 4: Run — pass.**
- [ ] **Step 5: Commit** `cw-domain: BragConfiguration model + mutation`.

### Task 5: `BragStatValue` display enum

**Files:** Modify `brag_sheet.rs`.

**Interfaces — Produces:**
- `enum BragStatValue` with variants (port from `BragSheetStatValue.swift`): `Count(i64)`,
  `Distance{km:f64}`, `Duration{seconds:f64}`, `Rate{value:f64,label:String}`,
  `Contact{callsign:String,distance_km:Option<f64>,band:Option<String>}`,
  `Power{watts:f64,callsign:String,distance_km:Option<f64>,band:Option<String>}`,
  `Efficiency{watts_per_mile:f64,detail:String}`, `Progress{current:i64,total:i64}`,
  `Streak{current:i64,longest:i64}`, `BandTable(Vec<BandTableEntry>)`,
  `DayOfWeek{day:String,count:i64}`, `CallsignCount{callsign:String,count:i64}`,
  `TimeOfDay{unix_seconds:i64}`, `ParkDetail{park:String,date:Option<String>,count:i64}`,
  `ModeStreakList(Vec<ModeStreakEntry>)`, `Wpm(i64)`, `Rst{value:String,detail:Option<String>}`,
  `NoData`.
- `struct BandTableEntry { band:String, callsign:String, distance_km:Option<f64> }`
- `struct ModeStreakEntry { mode:String, current:i64, longest:i64 }`
- `impl BragStatValue { fn has_data(&self)->bool; fn formatted(&self)->String;
  fn hero_value(&self)->String }` — port formatting from `BragSheetStatRendering.swift`
  and `BragSheetStatValue.swift` display helpers L91-142 (canonical strings: `"0312Z"`,
  `"38/50"`, distance/rate formatting). Distance formatting must match the Swift path
  (km→display units).

- [ ] **Step 1: Failing tests** (port expected strings from Swift):
```rust
#[test] fn progress_formats_fraction() { assert_eq!(BragStatValue::Progress{current:38,total:50}.formatted(), "38/50"); }
#[test] fn time_of_day_formats_zulu() { /* unix → "0312Z" */ }
#[test] fn no_data_has_no_data() { assert!(!BragStatValue::NoData.has_data()); }
```
- [ ] **Step 2: Run — fail. Step 3: Implement. Step 4: Run — pass.**
- [ ] **Step 5: Commit** `cw-domain: BragStatValue + canonical formatting`.

---

## PHASE 2 — Compute orchestration + FFI

### Task 6: `compute_configured_brag` orchestration in cw-store

**Files:** Modify `rust/cw-core/cw-store/src/analytics.rs`; add integration test in
`cw-store/src/testing` (follow existing test fixtures there).

**Interfaces — Consumes:** existing `brag_distance_stats`, `brag_streaks`, `brag_records`,
`brag_session_stats`, `brag_geographic`, `brag_pota`, `brag_period_metrics`,
`brag_average_rst`; `cw_domain::brag_sheet::{BragStatType, BragStatValue, BragPeriod}`.
**Produces:**
- `fn compute_configured_brag(&self, query:&ParsedQuery, enabled:&[BragStatType],
  start:Option<i64>, end:Option<i64>, today:NaiveDate) -> Result<Vec<(BragStatType, BragStatValue)>>`
  — for each enabled stat, pull the value from the appropriate aggregate bundle (compute
  each aggregate at most once, memoized within the call), mapping to `BragStatValue`.

**Mapping reference:** `BragSheetComputationActor+RustOverlay.swift` — its per-category
mappers show exactly which aggregate field feeds which stat. Port that mapping.

- [ ] **Step 1: Failing test** — build a fixture store (reuse the pattern in
  `cw-store/src/testing`), insert a handful of QSOs with known grids/power/parks, call
  `compute_configured_brag` with `enabled = BragStatType::all()`, assert a few known
  values (total QSOs, furthest contact, parks activated).
- [ ] **Step 2: Run — fail** `cargo test -p cw-store compute_configured_brag`.
- [ ] **Step 3: Implement** the orchestration: compute the aggregate bundles once, then a
  `match stat` producing each `BragStatValue`. Audit for any stat the Rust aggregates
  don't yet cover (RustOverlay may have Swift-only fallbacks); if found, add the aggregate
  to `analytics.rs` in this task (extend the relevant `brag_*` fn) — do NOT leave a gap.
- [ ] **Step 4: Run — pass.**
- [ ] **Step 5: Commit** `cw-store: compute_configured_brag orchestration (58-stat dispatch)`.

### Task 7: `BragSheetApi` FFI facade + Ffi types

**Files:** Create `rust/cw-core/cw-ffi/src/brag_sheet_api.rs`; modify `cw-ffi/src/lib.rs`
(`mod brag_sheet_api;`). Follow `session_wizard_api.rs` structure exactly.

**Interfaces — Produces (uniffi):**
- `#[derive(uniffi::Enum)] FfiBragStatType`, `FfiBragCategory`, `FfiBragPeriod`,
  `FfiBragPreset`, `FfiBragStatValue` (+ `From`/`Into` cw-domain).
- `#[derive(uniffi::Record)] FfiBragStatMeta { stat_type, display_name, short_display_name,
  category, icon_key }`, `FfiBragCategoryMeta`, `FfiBragPresetInfo`,
  `FfiBragPeriodConfig`, `FfiBragConfiguration`, `FfiBragStatResult { stat_type, value,
  formatted, icon_key }`.
- `#[uniffi::export] impl BragSheetApi { #[uniffi::constructor] fn new(store:Arc<FieldStore>)->Self;
  fn catalog(&self)->Vec<FfiBragStatMeta>; fn categories(&self)->Vec<FfiBragCategoryMeta>;
  fn presets(&self)->Vec<FfiBragPresetInfo>; fn load_config(&self)->Result<FfiBragConfiguration,CwError>;
  fn save_config(&self, cfg:FfiBragConfiguration)->Result<(),CwError>;
  fn compute_brag(&self, period:FfiBragPeriod, now_unix:i64)->Result<Vec<FfiBragStatResult>,CwError> }`
- `load_config`/`save_config` read/write cw-store `kv` key `"brag_sheet_configuration"`
  (JSON via serde over `BragConfiguration`); missing key → `BragConfiguration::default()`.
- `compute_brag` resolves the period window, reads config, calls
  `store.compute_configured_brag`, maps results (structured value + `formatted()` +
  `icon_key`).

- [ ] **Step 1: Failing test** (`cw-ffi` unit test): construct a `BragSheetApi` over an
  in-memory `FieldStore`, assert `catalog().len()==58`, `presets().len()==7`,
  `load_config()` returns defaults, `save_config`→`load_config` roundtrips, and
  `compute_brag(AllTime, now)` returns one result per enabled stat.
- [ ] **Step 2: Run — fail** `cargo test -p cw-ffi brag`.
- [ ] **Step 3: Implement** facade + Ffi conversions + kv persistence.
- [ ] **Step 4: Run — pass.**
- [ ] **Step 5: Full workspace build + clippy** `cargo build && cargo clippy` (whole
  `rust/cw-core`). Commit `cw-ffi: BragSheetApi facade (catalog/config/compute)`.

### Task 8: Regenerate FFI bindings (Swift xcframework + Kotlin)

**Files:** generated artifacts under iOS `Vendored/` and Android `uniffi/cw_ffi/`.

- [ ] **Step 1:** Run the xcframework build script
  `rust/cw-core/scripts/build-xcframework.sh` (per `feedback_worktree_ios_builds` /
  `reference_android_build_env`), and the Kotlin binding regen (cargo-ndk path in
  `android/build-rust.sh`).
- [ ] **Step 2:** Verify generated Swift exposes `BragSheetApi` and `FfiBrag*`; verify
  `uniffi/cw_ffi/cw_ffi.kt` exposes `BragSheetApi`.
- [ ] **Step 3: Commit** `ffi: regenerate Swift + Kotlin bindings for BragSheetApi`.

---

## PHASE 3 — iOS swap + delete Swift

### Task 9: Golden parity test (guards the swap — MUST pass before Task 10)

**Files:** Create `swift/ios/CarrierWaveTests/BragSheetParityTests.swift` (Simulator target
— `#filePath` fixtures fail on device per `feedback_test_harness_device_vs_sim`).

- [ ] **Step 1:** Build a fixture QSO set (reuse an existing test fixture log if present).
  Compute all 58 stats for all 3 periods via the **current Swift**
  `BragSheetComputationActor` AND via `BragSheetApi.compute_brag`.
- [ ] **Step 2:** Assert structured values + `formatted` strings match for every stat/period.
- [ ] **Step 3:** Run on Simulator (Makefile/xcodebuild per the parity-test note). Fix any
  mismatch **in Rust** (Rust is the new source of truth; match documented Swift behavior).
- [ ] **Step 4: Commit** `test(ios): brag sheet Rust↔Swift golden parity (58 stats × 3 periods)`.

### Task 10: Swap `AsyncBragSheetStats` onto `BragSheetApi`; delete Swift compute

**Files:** Modify `AsyncBragSheetStats.swift`, `BragSheetStatRendering.swift`, brag views;
add a thin `BragSheet` Swift adapter (typealiases / small wrappers over `Ffi*` so views
compile with minimal churn). Delete the Swift compute + domain enums (see File structure).

- [ ] **Step 1:** Introduce a thin adapter exposing `Ffi*` brag types under the names the
  views use (watch for app-target enum shadowing — `feedback_quick_entry_app_wrapper_shadow`).
- [ ] **Step 2:** Rewrite `AsyncBragSheetStats` to call `BragSheetApi.compute_brag` /
  `load_config` / `save_config` (off the shared `FieldStore`); drop the SwiftData snapshot
  path. Keep the `@Observable`/MainActor surface the views bind to.
- [ ] **Step 3:** Reduce `BragSheetStatRendering.swift` to view composition over
  `FfiBragStatResult.formatted` + `icon_key`→SF Symbol mapping.
- [ ] **Step 4:** Delete `BragSheetComputationActor*` (+4 ext), `BragSheetSnapshot`, and the
  6 domain enum files. Grep for every reference and fix call sites.
- [ ] **Step 5:** `xc build` (device generic) until clean; `xc test-core` + run the parity
  test on Simulator. Update iOS `FILE_INDEX.md`.
- [ ] **Step 6: Commit** `ios: route brag sheet through Rust BragSheetApi; delete Swift compute`.

### Task 11: iOS config migration (UserDefaults → cw-store kv)

**Files:** Add a one-time migration (e.g. in the brag feature's entry or app-launch
migration site used by prior kv migrations).

- [ ] **Step 1: Failing test** — seed `UserDefaults["bragSheetConfiguration"]` with a real
  legacy blob + empty kv; run migration; assert kv now holds the equivalent config and the
  migration is idempotent (second run no-ops).
- [ ] **Step 2:** Implement: if kv key empty AND UserDefaults blob present, decode + write to
  kv via `BragSheetApi.save_config`, then leave a migrated marker (or rely on kv-present).
- [ ] **Step 3:** Build + run test. **Step 4: Commit** `ios: migrate brag config to cw-store kv`.

---

## PHASE 4 — Android UI (net-new)

### Task 12: `BragSheetViewModel` on `BragSheetApi`

**Files:** Create `.../ui/brag/BragSheetViewModel.kt`. Reference `HomeViewModel.kt` for the
store-access + `Dispatchers.IO` pattern.

- [ ] **Step 1:** ViewModel exposing `catalog`, `presets`, `configuration`, and per-period
  `List<FfiBragStatResult>` state; all FFI calls in `withContext(Dispatchers.IO)`.
- [ ] **Step 2:** `loadConfig`, `saveConfig`, `computeBrag(period)`, `toggleStat`,
  `toggleHero`, `applyPreset` delegating to `BragSheetApi`.
- [ ] **Step 3:** Build (`./gradlew :app:assembleDebug`). Commit
  `android: BragSheetViewModel over shared BragSheetApi`.

### Task 13: `BragSheetScreen` + `BragSheetCustomizeScreen` (Compose)

**Files:** Create `.../ui/brag/BragSheetScreen.kt`, `BragSheetCustomizeScreen.kt`; wire into
the bottom-nav/More per `project_android_ios_tab_parity`.

- [ ] **Step 1:** `BragSheetScreen`: period selector (weekly/monthly/all-time), hero cards
  (up to 4), category-grouped stat list rendering `formatted` + `icon_key`→Material icon.
- [ ] **Step 2:** `BragSheetCustomizeScreen`: preset picker, per-stat enable/hero toggles,
  reorder; map/equipment/badge switches; persists via ViewModel.
- [ ] **Step 3:** Icon-key→Material mapping table (mirror the semantic keys from Task 1).
- [ ] **Step 4:** Build + launch on `cw_test` AVD (`reference_android_build_env`); smoke-test
  navigation + a preset switch. Commit `android: brag sheet + customize screens`.

---

## PHASE 5 — Cleanup

### Task 14: Docs, indexes, changelog

- [ ] **Step 1:** Update Rust `FILE_INDEX.md` (new `brag_sheet.rs`, `brag_sheet_api.rs`) and
  iOS `FILE_INDEX.md` (deleted files, thinned files).
- [ ] **Step 2:** Add `CHANGELOG.md` `[Unreleased]` entry (feature parity on Android,
  brag config now shared/sync-ready on iOS). If a `MARKETING_VERSION` bump ships this, add a
  `WhatsNewEntry` (per root CLAUDE.md).
- [ ] **Step 3:** Final full builds: `cargo test` (cw-core), `xc build`, `./gradlew assembleDebug`.
- [ ] **Step 4: Commit** `docs: brag sheet port — indexes + changelog`.

---

## Self-review notes

- **Spec coverage:** catalog (T1), categories (T1), periods (T2), presets (T3), config +
  mutation (T4), StatValue + formatting (T5), compute orchestration (T6), FFI facade +
  kv persistence (T7), bindings (T8), parity guard (T9), iOS swap + delete (T10),
  config migration (T11), Android VM (T12) + UI (T13), cleanup (T14). All design sections
  mapped.
- **Ordering guard:** T9 (parity) strictly precedes T10 (delete Swift).
- **Risks tracked in design:** stat-coverage gap (handled in T6 audit), distance parity
  (T6/T9), streak UTC bucketing (T2/T9), kv sync semantics (confirm in T7 — gate brag
  config out of sync if per-device layouts shouldn't sync).
- **Type consistency:** `compute_configured_brag` (T6) is the exact name consumed by T7;
  `FfiBragStatResult{stat_type,value,formatted,icon_key}` consumed by T10/T12/T13.

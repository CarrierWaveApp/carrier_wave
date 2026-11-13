# Map Rust Port — Phase B Implementation Plan (Embedded Map Cards)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the seven embedded map card surfaces (session logger map, session detail card, timeline replay, QSO detail arc, callsign map section, spots mini-map, club map) onto shared Rust, with full Android parity including new host surfaces, and delete iOS's duplicate geo math and hand-rolled QRZ/HamDB clients.

**Architecture:** New pure curves module in `cw-domain` (`timeline.rs`); lat/lon added to the cw-net callbook clients; a `callbook_location` cache table in cw-store (schema v13); `MapApi` grows three store-pure card methods (`session_map`, `session_timeline`, `qso_detail_map`); `QrzApi` grows a store-backed batch `locate`. iOS deletes `TimelineMapDataActor`, `ClubMapView+Lookup`, `HamDBClient.swift`, `MemberLocationCache.swift`, and all duplicate grid/distance math. Android gains the missing host surfaces.

**Tech Stack:** Rust (rusqlite, uniffi, chrono, tokio for locate concurrency), Swift/MapKit, Kotlin/Compose + osmdroid.

**Spec:** `docs/plans/2026-07-19-map-rust-port-phase-b-design.md`

## Global Constraints

- **Never run `cargo fmt`** in `rust/cw-core` (hand-formatted; gate is build + clippy + test).
- cw-store ids are **lowercase**; never feed Swift `.uuidString` (uppercase) into FFI ids.
- iOS compile-check: `xc` skill, destination `generic/platform=iOS`. **Never** launch the Simulator or UI tests.
- Rust gates: `cargo build` → `cargo clippy --all-targets` → `cargo test` from `rust/cw-core/`.
- Android build: `JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home ./gradlew :app:assembleDebug` from `android/`; grep output for `BUILD SUCCESSFUL`.
- iOS FFI restage: `./scripts/build-xcframework.sh` from `rust/cw-core/` after any cw-ffi signature change, **before** building iOS.
- swiftformat → swiftlint before any iOS commit.
- **Never `print`/`os_log`/`Logger`** in iOS app code — route through `RadioService.shared.addLog` or the domain's in-app log.
- Timeline constants (verbatim from Swift, port exactly): spot fade **300 s → 600 s** linear; decay fraction **1.0 − 0.7 × min(age/600, 1)**; SNR marker size **10–36 pt over 0–40 dB clamped**; SNR color bands **≥25 green / ≥15 blue / ≥5 orange / else red** (band indices 3/2/1/0).
- Callbook cache TTL: **30 days** (2,592,000 s), matching `MemberLocationCache`.
- Locate concurrency: **3-wide** with **200 ms** politeness delay between batches (from `ClubMapView+Lookup.fetchUncachedMembers`). Timeline spotter lookups cap at **30** callsigns per load (from `TimelineMapDataActor.maxLookups`).
- Skimmer suffix strip: everything from the **last `-`** (e.g. `KM3T-#` → `KM3T`, `W3LPL-1` → `W3LPL`).
- Commit after every task.

---

### Task 1: `cw-domain` timeline curves + skimmer strip

**Files:**
- Create: `rust/cw-core/cw-domain/src/timeline.rs`
- Modify: `rust/cw-core/cw-domain/src/lib.rs` (add `pub mod timeline;` in alphabetical position)
- Test: inline `#[cfg(test)] mod tests`

**Interfaces:**
- Produces (used by Tasks 5, 8, 14):
  - `spot_opacity(age_secs: f64) -> f64`
  - `spot_decay_fraction(age_secs: f64) -> f64`
  - `snr_marker_size(snr: Option<i64>) -> f64`
  - `snr_color_band(snr: i64) -> u8` — 0 red, 1 orange, 2 blue, 3 green
  - `strip_skimmer_suffix(callsign: &str) -> &str`

- [ ] **Step 1: Write the failing tests**

```rust
#[cfg(test)]
mod tests {
    use super::*;

    // Pinning tests: values captured from TimelineMapView.swift:212-242 and
    // SpotsMiniMapView.swift:108-115 before deletion.
    #[test]
    fn opacity_is_full_then_fades_linearly() {
        assert_eq!(spot_opacity(0.0), 1.0);
        assert_eq!(spot_opacity(299.9), 1.0);
        assert!((spot_opacity(450.0) - 0.5).abs() < 1e-9);
        assert_eq!(spot_opacity(600.0), 0.0);
        assert_eq!(spot_opacity(10_000.0), 0.0);
    }

    #[test]
    fn decay_fraction_reaches_point_three() {
        assert_eq!(spot_decay_fraction(0.0), 1.0);
        assert!((spot_decay_fraction(300.0) - 0.65).abs() < 1e-9);
        assert!((spot_decay_fraction(600.0) - 0.3).abs() < 1e-9);
        assert!((spot_decay_fraction(1200.0) - 0.3).abs() < 1e-9);
    }

    #[test]
    fn snr_size_clamps_0_to_40() {
        assert_eq!(snr_marker_size(None), 10.0);
        assert_eq!(snr_marker_size(Some(-5)), 10.0);
        assert!((snr_marker_size(Some(20)) - 23.0).abs() < 1e-9);
        assert_eq!(snr_marker_size(Some(40)), 36.0);
        assert_eq!(snr_marker_size(Some(99)), 36.0);
    }

    #[test]
    fn snr_bands() {
        assert_eq!(snr_color_band(-3), 0);
        assert_eq!(snr_color_band(5), 1);
        assert_eq!(snr_color_band(15), 2);
        assert_eq!(snr_color_band(24), 2);
        assert_eq!(snr_color_band(25), 3);
    }

    #[test]
    fn skimmer_suffix_strips_last_dash() {
        assert_eq!(strip_skimmer_suffix("KM3T-#"), "KM3T");
        assert_eq!(strip_skimmer_suffix("W3LPL-1"), "W3LPL");
        assert_eq!(strip_skimmer_suffix("N4ZR"), "N4ZR");
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cargo test -p cw-domain timeline` (from `rust/cw-core/`)
Expected: compile error.

- [ ] **Step 3: Implement**

```rust
//! Timeline replay curves + RBN spotter helpers. Port of the playback math in
//! iOS `TimelineMapView` (spotOpacity/spotDecayFraction/snrCircleSize) and the
//! SNR color banding in `SpotsMiniMapView.snrColor`, plus
//! `TimelineMapDataActor.stripSkimmerSuffix`. Pure functions so both
//! platforms render replay identically.

/// Spots render at full opacity for this many seconds…
pub const SPOT_FADE_START_SECS: f64 = 300.0;
/// …then fade linearly to zero at this age.
pub const SPOT_FADE_END_SECS: f64 = 600.0;

pub fn spot_opacity(age_secs: f64) -> f64 {
    if age_secs < SPOT_FADE_START_SECS {
        return 1.0;
    }
    if age_secs >= SPOT_FADE_END_SECS {
        return 0.0;
    }
    1.0 - (age_secs - SPOT_FADE_START_SECS) / (SPOT_FADE_END_SECS - SPOT_FADE_START_SECS)
}

/// 1.0 at birth decaying to 0.3 at the 10-minute limit.
pub fn spot_decay_fraction(age_secs: f64) -> f64 {
    let fraction = (age_secs / SPOT_FADE_END_SECS).min(1.0);
    1.0 - 0.7 * fraction
}

/// SNR (typically 0–40 dB) → marker diameter in points (10–36).
pub fn snr_marker_size(snr: Option<i64>) -> f64 {
    let Some(snr) = snr else { return 10.0 };
    let clamped = snr.clamp(0, 40) as f64;
    10.0 + 26.0 * (clamped / 40.0)
}

/// SNR → color band index: 0 red (<5), 1 orange (5..15), 2 blue (15..25),
/// 3 green (>=25). Clients map indices to platform colors.
pub fn snr_color_band(snr: i64) -> u8 {
    match snr {
        s if s >= 25 => 3,
        s if s >= 15 => 2,
        s if s >= 5 => 1,
        _ => 0,
    }
}

/// Strip an RBN skimmer suffix: everything from the last `-`.
pub fn strip_skimmer_suffix(callsign: &str) -> &str {
    match callsign.rfind('-') {
        Some(idx) => &callsign[..idx],
        None => callsign,
    }
}
```

Register `pub mod timeline;` in `lib.rs`.

- [ ] **Step 4: Run tests** — `cargo test -p cw-domain timeline` → 5 passed.

- [ ] **Step 5: Commit**

```bash
git add rust/cw-core/cw-domain/src/timeline.rs rust/cw-core/cw-domain/src/lib.rs
git commit -m "rust: timeline replay curves + skimmer suffix strip (map port phase B)"
```

---

### Task 2: cw-net lat/lon in QRZ + HamDB clients

**Files:**
- Modify: `rust/cw-core/cw-net/src/qrz.rs`
- Modify: `rust/cw-core/cw-net/src/hamdb.rs`
- Test: extend the inline test modules

**Interfaces:**
- Produces: `QrzLookup { …, pub lat: Option<f64>, pub lon: Option<f64> }`, `HamdbLookup { …, pub lat: Option<f64>, pub lon: Option<f64> }`. Additive; existing consumers unaffected.

- [ ] **Step 1: Write the failing tests**

In `qrz.rs` tests, add `<lat>33.747</lat><lon>-112.246</lon>` inside the `LOOKUP_XML` `<Callsign>` block and assert:

```rust
    #[test]
    fn parses_lat_lon() {
        let found = parse_lookup(LOOKUP_XML, "aa7bq").expect("record");
        assert_eq!(found.lat, Some(33.747));
        assert_eq!(found.lon, Some(-112.246));
    }

    #[test]
    fn missing_lat_lon_is_none() {
        let xml = "<Callsign><call>W1AW</call><fname>H</fname></Callsign>";
        let found = parse_lookup(xml, "w1aw").expect("record");
        assert_eq!(found.lat, None);
        assert_eq!(found.lon, None);
    }
```

In `hamdb.rs` tests, add `"lat":"41.714775","lon":"-72.727260"` to the `parses_full_record` body and assert `found.lat == Some(41.714775)`, `found.lon == Some(-72.727260)`; in `not_found_status_is_none`'s body add `"lat":"NOT_FOUND","lon":"NOT_FOUND"` (already returns `None` overall — this pins that `NOT_FOUND` placeholders don't panic the parse).

- [ ] **Step 2: Run to verify failure** — `cargo test -p cw-net qrz hamdb` → compile errors (missing fields).

- [ ] **Step 3: Implement**

`qrz.rs`: add `pub lat: Option<f64>, pub lon: Option<f64>` to `QrzLookup`; in `parse_lookup` add:

```rust
    let lat = parse_xml_value(xml, "lat").and_then(|v| v.parse::<f64>().ok());
    let lon = parse_xml_value(xml, "lon").and_then(|v| v.parse::<f64>().ok());
```

and include both in the struct literal (also add `lat: None, lon: None` anywhere `..Default::default()` isn't used — `Default` derive covers the test fixtures).

`hamdb.rs`: add `lat: Option<String>, lon: Option<String>` to `HamdbLicense` (HamDB returns them as strings); add `pub lat: Option<f64>, pub lon: Option<f64>` to `HamdbLookup`; in `lookup` (and the test-local `parse`):

```rust
            lat: nonempty(lic.lat).and_then(|v| v.parse::<f64>().ok()),
            lon: nonempty(lic.lon).and_then(|v| v.parse::<f64>().ok()),
```

(`nonempty` already maps `"NOT_FOUND"` → `None`, which handles the miss placeholder.)

- [ ] **Step 4: Run tests** — `cargo test -p cw-net` → all pass. `cargo clippy -p cw-net --all-targets` clean. Also `cargo build` workspace — `merge_callbook` in `cw-ffi/src/qrz_api.rs:148` will need the two new fields merged (QRZ value wins, HamDB fills nil — same pattern as the existing fields); fix it in this task since the workspace must build.

- [ ] **Step 5: Commit**

```bash
git add rust/cw-core/cw-net/src/qrz.rs rust/cw-core/cw-net/src/hamdb.rs rust/cw-core/cw-ffi/src/qrz_api.rs
git commit -m "rust: parse lat/lon in QRZ + HamDB callbook clients (map port phase B)"
```

---

### Task 3: cw-store `callbook_location` cache (schema v13)

**Files:**
- Create: `rust/cw-core/cw-store/src/callbook_location.rs`
- Modify: `rust/cw-core/cw-store/src/migrations.rs` (`SCHEMA_VERSION` 12 → 13; add the v13 migration following the existing per-version pattern in `migrate()`)
- Modify: `rust/cw-core/cw-store/src/lib.rs` (declare `mod callbook_location;`, re-export types like the other modules)
- Test: inline `#[cfg(test)] mod tests` (reuse the in-memory store fixture pattern from `session_spot.rs` tests)

**Interfaces:**
- Produces (used by Tasks 4–5):

```rust
#[derive(Debug, Clone, PartialEq)]
pub struct CallbookLocation {
    pub callsign: String,      // uppercase, base call (skimmer suffix stripped by callers)
    pub latitude: f64,
    pub longitude: f64,
    pub grid: Option<String>,
    pub source: String,        // "qrz" | "hamdb" | "grid"
    pub fetched_at: i64,       // unix seconds
}
```

  - `pub fn upsert_callbook_location(&self, loc: &CallbookLocation) -> Result<()>`
  - `pub fn fetch_callbook_locations(&self, callsigns: &[String], now: i64, ttl_secs: i64) -> Result<Vec<CallbookLocation>>` — only rows with `fetched_at > now - ttl_secs`; input matched case-insensitively (store uppercase, compare `UPPER(?)`).

- [ ] **Step 1: Write the failing tests**

```rust
    #[test]
    fn upsert_and_fetch_roundtrip() {
        // upsert one row; fetch with matching callsign (lowercase input) →
        // 1 row with identical fields
    }

    #[test]
    fn fetch_expires_by_ttl() {
        // row fetched_at = now - 40 days; fetch with ttl 30 days → empty;
        // fetch with ttl 60 days → 1 row
    }

    #[test]
    fn upsert_replaces_existing() {
        // upsert same callsign twice with different lat; fetch → newest lat
    }
```

Write these fully with the fixture helpers.

- [ ] **Step 2: Run to verify failure** — `cargo test -p cw-store callbook` → compile error.

- [ ] **Step 3: Implement**

Migration (v13 arm in `migrate()`):

```sql
CREATE TABLE IF NOT EXISTS callbook_location (
    callsign    TEXT PRIMARY KEY,
    latitude    REAL NOT NULL,
    longitude   REAL NOT NULL,
    grid        TEXT,
    source      TEXT NOT NULL,
    fetched_at  INTEGER NOT NULL
);
```

`callbook_location.rs`: `INSERT … ON CONFLICT(callsign) DO UPDATE SET` upsert (uppercase the callsign on write); fetch builds a `?,?,…` placeholder list over `WHERE callsign IN (…) AND fetched_at > ?` with inputs uppercased. Follow the prepare/query_map style of `session_spot.rs`.

- [ ] **Step 4: Run tests** — `cargo test -p cw-store callbook` → 3 passed; clippy clean.

- [ ] **Step 5: Commit**

```bash
git add rust/cw-core/cw-store/src/callbook_location.rs rust/cw-core/cw-store/src/migrations.rs rust/cw-core/cw-store/src/lib.rs
git commit -m "rust: callbook_location cache table, schema v13 (map port phase B)"
```

---

### Task 4: `QrzApi.locate` batch lookup

**Files:**
- Modify: `rust/cw-core/cw-ffi/src/qrz_api.rs`
- Test: inline unit tests for the pure pieces; network flow covered by the existing QrzApi test approach (mock base URLs via `with_base_url` if the existing tests do; otherwise unit-test `location_from_lookup` only)

**Interfaces:**
- Consumes: `CallbookLocation` store API (Task 3), `cw_net::{QrzClient, HamdbClient}` with lat/lon (Task 2), `cw_domain::maidenhead` for grid centroids, existing `lookup_callbook` merge flow.
- Produces (used by Tasks 8, 10, 11, 14):

```rust
#[derive(uniffi::Record)]
pub struct FfiCallsignLocation {
    pub callsign: String,      // uppercase base call as queried
    pub latitude: f64,
    pub longitude: f64,
    pub grid: Option<String>,
    pub source: String,        // "qrz" | "hamdb" | "grid"
}
```

  - `#[uniffi::constructor] QrzApi::with_store(secure: Arc<dyn SecureStore>, store: Arc<FieldStore>) -> Result<Arc<Self>, CwError>` — existing `new` unchanged; `QrzApi` gains `store: Option<Arc<FieldStore>>` (`None` from `new`).
  - `pub async fn locate(&self, callsigns: Vec<String>) -> Result<Vec<FfiCallsignLocation>, CwError>`

**Locate semantics (port of `ClubMapView+Lookup` + `MemberLocationCache`, exactly):**
1. Uppercase + trim + dedupe inputs; drop empties.
2. Read `fetch_callbook_locations(inputs, now, 30 days)` — cache hits return immediately in the result.
3. For misses: process in chunks of **3** concurrent lookups with a **200 ms** sleep between chunks (`tokio::time::sleep`). Each lookup runs the `lookup_callbook` QRZ→HamDB flow (reuse the existing private helpers; QRZ skipped when no credentials, exactly as `lookup_callbook` behaves today).
4. Coordinate resolution per result: raw `lat`/`lon` when both present (source `"qrz"`/`"hamdb"` per which client supplied them — QRZ wins on merge); else grid centroid via `cw_domain::maidenhead` coordinate (source `"grid"`); else skip (no cache write — misses are retried next call, matching `MemberLocationCache` which only persists successes).
5. Upsert successes into `callbook_location` with `fetched_at = now`.
6. Errors on individual lookups are skipped, not fatal; `locate` only errors if the store is absent (constructed via `new`) → `CwError` with message `"locate requires a store-backed QrzApi"`.

- [ ] **Step 1: Write failing unit tests** for the pure coordinate resolution:

```rust
    #[test]
    fn location_prefers_raw_lat_lon_over_grid() { /* lookup with lat/lon + grid → source qrz/hamdb, raw coords */ }
    #[test]
    fn location_falls_back_to_grid_centroid() { /* lookup with grid only → maidenhead centroid, source "grid" */ }
    #[test]
    fn location_none_without_coords_or_grid() { /* neither → None */ }
```

- [ ] **Step 2: Run to verify failure** — `cargo test -p cw-ffi qrz` → compile error.

- [ ] **Step 3: Implement** — factor `fn location_from_lookup(callsign: &str, merged: &FfiQrzLookup) -> Option<FfiCallsignLocation>` (pure, tested above), then the async `locate` per the semantics block. Timestamp source: follow whatever existing cw-ffi code uses for "now" (grep for `SystemTime::now` usage in cw-ffi and match it).

- [ ] **Step 4: Run gates** — `cargo build && cargo clippy --all-targets && cargo test -p cw-ffi` → clean.

- [ ] **Step 5: Commit**

```bash
git add rust/cw-core/cw-ffi/src/qrz_api.rs
git commit -m "rust: QrzApi.locate batch callbook location lookup with cache (map port phase B)"
```

---

### Task 5: `MapApi` card methods (`session_map`, `session_timeline`, `qso_detail_map`) + curve exports

**Files:**
- Create: `rust/cw-core/cw-ffi/src/map_api/cards.rs`
- Modify: `rust/cw-core/cw-ffi/src/map_api/records.rs` (new records below)
- Modify: `rust/cw-core/cw-ffi/src/map_api/mod.rs` (methods + free exports; declare `mod cards;`)
- Modify: `rust/cw-core/cw-store/src/map_data.rs` (timeline/session source queries)
- Test: store-backed integration tests in `cards.rs` + pure free-export tests in `mod.rs`

**Interfaces:**
- Consumes: `fetch_logging_session(id)` (`logging_session.rs:618`), `fetch_session_spots` (`session_spot.rs:159`), `fetch_rove_stops(session_id)` (`rove_stop.rs:101`), `fetch_callbook_locations` (Task 3), `cw_domain::timeline` (Task 1), existing `great_circle_segments`, `bounds_for`/`camera_spans`, maidenhead.
- Produces (new records, all `#[derive(uniffi::Record)]`):

```rust
pub struct FfiTimelineEvent {
    pub id: String,
    pub timestamp: i64,            // unix seconds
    pub is_qso: bool,              // false = RBN spot
    pub callsign: String,
    pub band: Option<String>,
    pub mode: Option<String>,
    pub latitude: Option<f64>,     // resolved event coordinate (their grid / spotter)
    pub longitude: Option<f64>,
    pub snr: Option<i64>,
    pub spotter: Option<String>,   // original spotter string incl. skimmer suffix
}

pub struct FfiTimelineData {
    pub events: Vec<FfiTimelineEvent>,   // sorted ascending by timestamp
    pub my_grid: Option<String>,
    pub my_latitude: Option<f64>,
    pub my_longitude: Option<f64>,
    pub started_at: i64,
    pub ended_at: i64,
    pub unresolved_spotters: Vec<String>, // base calls (suffix-stripped, deduped, max 30)
}

pub struct FfiSessionMapData {
    pub annotations: Vec<FfiQsoMapAnnotation>, // individual pins (session maps don't cluster)
    pub rove_stops: Vec<FfiCoordinate>,
    pub arcs: Vec<FfiMapArc>,
    pub bounds: Option<FfiMapBounds>,
}

pub struct FfiQsoDetailMap {
    pub my: Option<FfiCoordinate>,
    pub their: Option<FfiCoordinate>,
    pub their_source: String,       // "grid" | "park" | "none"
    pub arc: Vec<FfiMapPolyline>,   // empty unless both coordinates resolve
    pub distance_km: Option<f64>,
    pub bearing: Option<f64>,
}
```

  Methods on `MapApi` (store-pure — no network):
  - `session_map(session_id: String) -> Result<FfiSessionMapData, CwError>`
  - `session_timeline(session_id: String) -> Result<FfiTimelineData, CwError>`
  - `qso_detail_map(qso_id: String) -> Result<FfiQsoDetailMap, CwError>`

  Free exports (wrap `cw_domain::timeline`):
  - `timeline_spot_opacity(age_secs: f64) -> f64`
  - `timeline_spot_decay(age_secs: f64) -> f64`
  - `timeline_snr_marker_size(snr: Option<i64>) -> f64`
  - `timeline_snr_color_band(snr: i64) -> u8`

**Semantics (parity with the Swift being deleted):**
- `session_map`: QSOs of the session (rows via a new `map_data.rs` query: `logging_session_id = ?`, visible, ordered by qso_date asc) → **individual** annotations for rows with grid ≥ 4 chars (reuse the Phase A `individual_annotations` path in `aggregate.rs`); rove stops via `fetch_rove_stops`, coordinates from `my_grid` centroids (skip unresolvable, port of `SessionQSOMap.roveStopCoordinates:52-62`); arcs home→contact for rows with both grids (30 segments); bounds over all pins + home.
- `session_timeline` (port of `TimelineMapDataActor.loadEvents`): session via `fetch_logging_session`; QSO events = visible QSOs with `qso_date` in `[started_at, ended_at]` **window across all QSOs** (not session-filtered — faithful to `fetchQSOEvents:105-138`), limit 500, ascending; spot events = `fetch_session_spots` for the session (limit 2000), **RBN only** — replicate `SessionSpot.isRBN` exactly (grep `CarrierWaveData` for the `isRBN` definition and match its `source` comparison; do NOT guess). Spotter coordinate: `spotter_grid` if present, else `callbook_location` cache hit on the suffix-stripped base call; still-missing base calls (deduped, first 30) → `unresolved_spotters`. Merge + sort ascending. Skip-nothing: events with unresolved coordinates still appear (latitude/longitude `None`) — the client hides them off-map, matching Swift.
- `qso_detail_map` (port of `QSODetailView+Map.resolveMyLocation/resolveTheirLocation:39-73`): fetch the QSO by id (reuse the existing single-QSO fetch the other APIs use — grep cw-store for `fetch_qso`); `my` = my_grid centroid; `their` = their_grid centroid, else `pota_park` lat/lon by the QSO's park reference (source `"park"`), else `None` (`"none"`); arc + distance (haversine via maidenhead distance) + bearing only when both resolve.

- [ ] **Step 1: Write the failing tests** — store-backed fixtures in `cards.rs` (insert session + QSOs + spots + rove stops, following the analytics fixture pattern):

```rust
    #[test] fn session_map_pins_arcs_rove_stops() { /* 2 QSOs w/ grids + 1 rove stop → 2 annotations, 2 arcs, 1 rove coord, bounds some */ }
    #[test] fn session_timeline_merges_and_sorts() { /* 1 QSO + 2 RBN spots interleaved → 3 events ascending, is_qso flags right */ }
    #[test] fn session_timeline_window_not_session_scoped() { /* QSO in window w/o session id still appears */ }
    #[test] fn session_timeline_unresolved_spotters_stripped_deduped() { /* spots from "KM3T-#" and "KM3T-1" w/o grid, no cache → unresolved == ["KM3T"] */ }
    #[test] fn session_timeline_uses_callbook_cache() { /* upsert cache row for KM3T; spot from "KM3T-#" w/o grid → coordinates resolved, no unresolved */ }
    #[test] fn qso_detail_park_fallback() { /* QSO w/o their_grid but with park + pota_park row → their from park lat/lon, source "park" */ }
```

- [ ] **Step 2: Run to verify failure** — `cargo test -p cw-ffi cards` → compile error.

- [ ] **Step 3: Implement** — new `map_data.rs` queries:
  - `pub fn session_map_rows(&self, session_id: &str) -> Result<Vec<MapQsoRow>>` — reuses `MapQsoRow` (keeps its non-empty `their_grid` WHERE clause; gridless QSOs have nothing to pin on the session map, matching `mappableQSOs`).
  - `pub fn timeline_window_qsos(&self, start: i64, end: i64, limit: i64) -> Result<Vec<TimelineQsoRow>>` with a new slim row (do NOT reuse `MapQsoRow` — its `their_grid: String` is contractually non-empty, but timeline events legitimately lack grids):
    ```rust
    pub struct TimelineQsoRow {
        pub id: String,
        pub callsign: String,
        pub band: Option<String>,
        pub mode: Option<String>,
        pub qso_date: i64,
        pub their_grid: Option<String>,
    }
    ```
  `cards.rs` implements the three methods per the semantics block, each helper under ~60 lines. Free exports in `mod.rs` are one-line wrappers.

- [ ] **Step 4: Run full Rust gates** — `cargo build && cargo clippy --all-targets && cargo test` → clean.

- [ ] **Step 5: Commit**

```bash
git add rust/cw-core/cw-ffi/src/map_api rust/cw-core/cw-store/src/map_data.rs
git commit -m "rust: MapApi card methods session_map/session_timeline/qso_detail_map + timeline curve exports (map port phase B)"
```

---

### Task 6: Regenerate FFI artifacts

- [ ] **Step 1:** From `rust/cw-core/`: `./scripts/build-xcframework.sh` → vendored xcframework + `CwFfi+Generated.swift` restaged.
- [ ] **Step 2:** From `android/`: `JAVA_HOME=… ./gradlew :app:assembleDebug` → `BUILD SUCCESSFUL` in log; `grep -c "sessionTimeline\|FfiCallsignLocation" android/app/src/main/java/uniffi/cw_ffi/cw_ffi.kt` ≥ 1.
- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/java/uniffi/cw_ffi/cw_ffi.kt swift/packages/CarrierWaveCore/Sources/CarrierWaveCwFfi/CwFfi+Generated.swift
git commit -m "ffi: regen bindings with Phase B card methods + locate"
```

---

### Task 7: iOS grid/distance consolidation (session logger map, session detail card, callsign section, spots mini-map, QSO detail)

**Files:**
- Modify: `swift/ios/CarrierWave/Views/Map/SessionQSOMap.swift` (`mappableQSOs:36-43`, `roveStopCoordinates:52-62`)
- Modify: `swift/ios/CarrierWave/Views/Map/MapContentBuilders.swift` (`qsoAnnotations` grid lookup)
- Modify: `swift/ios/CarrierWave/Views/Sessions/SessionDetailView+Insights.swift` (`mappableQSOs:77-84`, `myCoord:96-102`)
- Modify: `swift/ios/CarrierWave/Views/Callsign/CallsignMapSection.swift` (coordinate `:17`, distance/bearing `:36-38`)
- Modify: `swift/ios/CarrierWave/Views/Logger/SpotsMiniMapView.swift` (delete `gridToCoordinates:118-152`; swap `snrColor:108-115` to `timelineSnrColorBand`)
- Modify: `swift/ios/CarrierWave/Views/Logs/QSODetailView+Map.swift` (use `MapApi.qsoDetailMap`; delete `resolveMyLocation`/`resolveTheirLocation`/`parkCoordinate:39-73` and the `HaversineDistance` footer math)

**Interfaces:**
- Consumes (Task 6 bindings): `maidenheadCoordinate(grid:)`, `maidenheadDistanceKm`, `maidenheadBearing`, `maidenheadIsValid`, `timelineSnrColorBand(snr:)`, `MapApi.qsoDetailMap(qsoId:)`.
- Produces: unchanged view behavior; `MaidenheadConverter` no longer referenced from any file in this task's list.

- [ ] **Step 1:** Swap every `MaidenheadConverter.coordinate(from:)` in the listed files to `maidenheadCoordinate(grid:)` (returns `FfiCoordinate?` — map to `CLLocationCoordinate2D`). `CallsignMapSection` distance label: `maidenheadDistanceKm(grid1:grid2:)` × 0.621371 for miles; bearing via `maidenheadBearing`. Keep `cardinalDirection` as-is.
- [ ] **Step 2:** `SpotsMiniMapView`: delete `gridToCoordinates`, use `maidenheadCoordinate`; replace `snrColor`'s switch with a `switch timelineSnrColorBand(snr: Int64(snr))` mapping 3→green, 2→blue, 1→orange, 0→red.
- [ ] **Step 3:** `QSODetailView+Map`: load via `MapApi.qsoDetailMap(qsoId: qso.id.uuidString.lowercased())` in a `.task`; render `my`/`their` pins, arc polylines from `arc`, distance footer from `distanceKm`. Delete the three resolver functions and the `POTAParksCache` fallback call (now in Rust). Keep `bandColor`.
- [ ] **Step 4:** Grep `MaidenheadConverter\.` across `swift/ios/CarrierWave/Views/Map/ Views/Sessions/ Views/Callsign/ Views/Logger/ Views/Logs/` — the only remaining hits must be outside this task's surfaces (QSOMapView's `updateGridOverlay` center-grid readout is Phase A scope, untouched).
- [ ] **Step 5:** swiftformat → swiftlint → `xc` compile-check (`generic/platform=iOS`). Fix to green.
- [ ] **Step 6: Commit** — `git add -A swift/ios && git commit -m "ios: map cards onto FFI grid/distance/curve functions; QSO detail via qso_detail_map (map port phase B)"`

---

### Task 8: iOS timeline replay cutover

**Files:**
- Delete: `swift/ios/CarrierWave/Views/Sessions/TimelineMapDataActor.swift`
- Modify: `swift/ios/CarrierWave/Views/Sessions/TimelineMapView.swift`
- Modify: `swift/ios/CarrierWave/Views/FILE_INDEX.md`

**Interfaces:**
- Consumes: `MapApi.sessionTimeline(sessionId:)`, `QrzApi.locate(callsigns:)` (store-backed constructor `QrzApi.withStore(secure:store:)` — grep how iOS constructs `QrzApi` today for the SecureStore bridge and reuse it), `timelineSpotOpacity`/`timelineSpotDecay`/`timelineSnrMarkerSize` free functions.
- Produces: same `TimelineMapEvent`-shaped view state, now built from `FfiTimelineEvent`.

- [ ] **Step 1:** Replace the actor load with: `sessionTimeline(sessionId)` → map events; if `unresolvedSpotters` non-empty, fire `try? await qrzApi.locate(callsigns: data.unresolvedSpotters)` then call `sessionTimeline` once more (cache-warm) and re-map. Keep `TimelineMapEvent` as the view's model (init from FFI record; `id` from the FFI string id).
- [ ] **Step 2:** Replace `spotOpacity`/`spotDecayFraction`/`snrCircleSize` bodies (`TimelineMapView.swift:212-242`) with calls to the FFI curve functions (age computed the same way from `currentDate`).
- [ ] **Step 3:** `git rm` the actor; grep `TimelineMapDataActor|TimelineLoadedData|TimelineSessionMetadata` — rehome `TimelineSessionMetadata` fields into the view from `FfiTimelineData` (`myLatitude`/`myLongitude`/`startedAt`/`endedAt`). Update FILE_INDEX.
- [ ] **Step 4:** Format/lint/compile-check to green.
- [ ] **Step 5: Commit** — `git commit -m "ios: timeline replay onto MapApi.session_timeline + shared curves; delete TimelineMapDataActor (map port phase B)"`

---

### Task 9: iOS club map cutover

**Files:**
- Delete: `swift/ios/CarrierWave/Views/Activity/ClubMapView+Lookup.swift`
- Delete: `swift/ios/CarrierWave/Services/HamDBClient.swift`
- Delete: `swift/ios/CarrierWave/Services/MemberLocationCache.swift`
- Modify: `swift/ios/CarrierWave/Views/Activity/ClubMapView.swift`
- Modify: `swift/ios/CarrierWave/Views/FILE_INDEX.md` + `Services` index if separate

**Interfaces:**
- Consumes: `QrzApi.withStore(…).locate(callsigns:)`, `maidenheadCoordinate`, `mapBoundsFor(coords:)`.
- Produces: grid-first render — member pins from `lastGrid` centroids immediately, then one `locate` call for **all** members (cache makes repeats cheap), re-render refined coordinates.

- [ ] **Step 1:** In `ClubMapView.swift`: build initial annotations from `member.lastGrid` → `maidenheadCoordinate` (skip nil). In `.task`, call `locate` with all member callsigns; merge results over the grid pins (precise lat/lon replaces centroid; members with no grid gain pins), re-render.
- [ ] **Step 2:** Replace `isWideSpan:90-102` and `regionForAnnotations:279-312` with `mapBoundsFor(coords:)` (`requiresGlobeView`, `cameraLatSpan`/`cameraLonSpan`). Keep `ClusteredMapView`, marker tinting, on-air logic.
- [ ] **Step 3:** `git rm` the three files. Grep `HamDBClient|MemberLocationCache|acquireQRZSessionKey|lookupCoordinatesVia` — `TimelineMapDataActor` is already gone (Task 8); no other consumers may remain. Also grep `QrzCallbookClient` to confirm it is untouched (other surfaces still use it).
- [ ] **Step 4:** Format/lint/compile-check to green.
- [ ] **Step 5: Commit** — `git commit -m "ios: club map grid-first + QrzApi.locate; delete hand-rolled QRZ/HamDB lookup + JSON cache (map port phase B)"`

---

### Task 10: Android club map refinement

**Files:**
- Modify: `android/app/src/main/java/app/carrierwave/android/ui/clubs/ClubMapView.kt`
- Modify: the clubs view-model that owns member state (grep `ui/clubs` for the ViewModel feeding `ClubMapView`) — add the locate call
- Modify: `android/app/src/main/java/app/carrierwave/android/CwApp.kt` (construct the store-backed `QrzApi` — follow how `CwApp` builds existing APIs; if a `QrzApi` already exists there, switch it to `QrzApi.withStore`)

**Interfaces:**
- Consumes: `QrzApi.withStore(secure, store).locate(callsigns)`, existing `maidenheadCoordinate`.
- Produces: grid-first pins, refined by locate results; members without grids gain pins.

- [ ] **Step 1:** Keep the current grid-centroid pins as the immediate render. In the view-model, launch `withContext(Dispatchers.IO) { qrzApi.locate(members.map { it.callsign }) }` (FFI is blocking/async — keep off Main per the uniffi-dispatcher rule), merge into a `Map<String, FfiCallsignLocation>`, and re-emit pin state (precise coords win; new pins for gridless members).
- [ ] **Step 2:** Build → `BUILD SUCCESSFUL`.
- [ ] **Step 3: Commit** — `git commit -m "android: club map grid-first pins refined via QrzApi.locate (map port phase B)"`

---

### Task 11: Android QSO detail + callsign map cards

**Files:**
- Create: `android/app/src/main/java/app/carrierwave/android/ui/map/QsoDetailMapCard.kt` (shared composable: pins + arc polylines + distance/bearing footer over an osmdroid `MapView`, consuming `FfiQsoDetailMap` — reuse the arc/marker helpers from `MapScreen.kt`; extract them to a new `MapRenderHelpers.kt` if needed rather than duplicating)
- Modify: the Logbook QSO detail screen (grep `ui/logbook` for the detail composable) — embed `QsoDetailMapCard`, loading via `mapApi.qsoDetailMap(qsoId)` on IO
- Create: `android/app/src/main/java/app/carrierwave/android/ui/callsign/CallsignMapSection.kt` — single-pin card: `maidenheadCoordinate(grid)` + `maidenheadDistanceKm`/`maidenheadBearing` labels (port of iOS `CallsignMapSection`, incl. cardinal direction mapping); embed it in the callsign/history surface if one exists, else in the QSO detail screen's callsign header area (grep `ui/` for where callsign detail renders; if no host exists, add the section to QSO detail — it is the callsign surface Android has)

**Interfaces:**
- Consumes: `mapApi.qsoDetailMap(qsoId)`, maidenhead free functions.

- [ ] **Step 1:** Build the two composables + wire hosts. Distance label: km → miles ×0.621371, matching iOS copy.
- [ ] **Step 2:** Build → `BUILD SUCCESSFUL`.
- [ ] **Step 3: Commit** — `git commit -m "android: QSO detail map card + callsign map section (map port phase B)"`

---

### Task 12: Android session detail map card + session map

**Files:**
- Create: `android/app/src/main/java/app/carrierwave/android/ui/sessions/SessionMapCard.kt` — thumbnail card + full-screen map over `mapApi.sessionMap(sessionId)`: individual pins, rove-stop markers, arcs, camera from `bounds` (reuse `frameBounds` from `MapScreen.kt` — move it into `MapRenderHelpers.kt` alongside the Task 11 extraction)
- Modify: the Android session detail screen (grep `ui/sessions` for the detail composable; if only the live logger exists, add a detail route from the session list — minimal screen: header + this card + timeline entry point for Task 14)

**Interfaces:**
- Consumes: `mapApi.sessionMap(sessionId)` (Task 5), `FfiSessionMapData`.

- [ ] **Step 1:** Build card + host wiring.
- [ ] **Step 2:** Build → `BUILD SUCCESSFUL`.
- [ ] **Step 3: Commit** — `git commit -m "android: session detail map card on MapApi.session_map (map port phase B)"`

---

### Task 13: Android spots mini-map

**Files:**
- Create: `android/app/src/main/java/app/carrierwave/android/ui/spots/SpotsMiniMap.kt` — port of iOS `SpotsMiniMapView`: markers per spot (color from `timelineSnrColorBand` for RBN — 3 green / 2 blue / 1 orange / 0 red — fixed colors per source otherwise, sizes from `timelineSnrMarkerSize`), arcs to the target callsign via `greatCircleArc`, coordinates via `maidenheadCoordinate`
- Modify: the spots screen (grep `ui/spots` for the SpotEngine tab composable) — add the mini-map as a collapsible header card above the list

**Interfaces:**
- Consumes: spot rows the screen already holds, `timelineSnrColorBand`/`timelineSnrMarkerSize`, `greatCircleArc`, `maidenheadCoordinate`.

- [ ] **Step 1:** Build + wire. **Step 2:** Build green. **Step 3: Commit** — `git commit -m "android: spots mini-map card (map port phase B)"`

---

### Task 14: Android timeline replay screen

**Files:**
- Create: `android/app/src/main/java/app/carrierwave/android/ui/sessions/TimelineReplayScreen.kt` — scrubber (slider 0…duration), play/pause with speed multiplier, osmdroid map rendering events ≤ current time with opacity `timelineSpotOpacity(age)`, size `timelineSnrMarkerSize`, decay `timelineSpotDecay`; QSO events as pins, RBN spots as circles; home marker from `myLatitude`/`myLongitude`
- Create: `android/app/src/main/java/app/carrierwave/android/ui/sessions/TimelineReplayViewModel.kt` — loads `mapApi.sessionTimeline(sessionId)` on IO; if `unresolvedSpotters` non-empty → `qrzApi.locate(...)` then reload once (mirror of iOS Task 8 flow); playback clock state
- Modify: session detail screen (Task 12) — "Replay" entry point navigating here

**Interfaces:**
- Consumes: `mapApi.sessionTimeline`, `qrzApi.locate`, timeline curve free functions.

- [ ] **Step 1:** ViewModel with load + locate-refine + playback tick (coroutine-driven, cancel on pause/dispose). **Step 2:** Screen rendering. **Step 3:** Build green. **Step 4: Commit** — `git commit -m "android: timeline replay screen on session_timeline + shared curves (map port phase B)"`

---

### Task 15: Docs, changelog, final gates

- [ ] **Step 1:** `CHANGELOG.md`: iOS `[Unreleased]` — club map faster first paint (grid-first) + shared map card engine; Android section — new cards/screens (QSO detail map, session detail map, callsign section, spots mini-map, timeline replay, club map precise pins).
- [ ] **Step 2:** Update `docs/plans/2026-07-19-map-rust-port-phase-a-handoff.md` (Phase B started/done note) and the relevant `FILE_INDEX.md` files (iOS deletions, Android creations) if not already done per-task.
- [ ] **Step 3:** Full gates end-to-end: Rust build/clippy/test; xcframework regen if any signature changed since Task 6; iOS compile-check; Android assembleDebug.
- [ ] **Step 4:** Device pass owed (both platforms): club map refine, timeline replay, each new Android card. Flag for Jay.
- [ ] **Step 5: Commit** — `git commit -m "docs: map Rust port phase B changelog + handoff updates"`

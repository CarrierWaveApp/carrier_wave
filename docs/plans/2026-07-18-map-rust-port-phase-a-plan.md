# Map Rust Port — Phase A Implementation Plan (MapApi core + QSO map)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the QSO-map view model (filtering, clustering, arcs, bounds, stats, grid overlay) into shared Rust (`MapApi` in cw-ffi), cut iOS over cleanly (delete the SwiftData map pipeline), and bring the Android Map tab to feature parity.

**Architecture:** New pure-math modules in `cw-domain` (`great_circle`, `map_bounds`); new SQL row/option fetchers in `cw-store`; a new `cw-ffi/src/map_api/` module exposing `MapApi.qso_map(filter)` plus free geo functions. iOS `QSOMapView` and Android `MapScreen` become thin renderers over `FfiQsoMapData`.

**Tech Stack:** Rust (rusqlite, uniffi proc-macros, chrono), Swift/MapKit, Kotlin/Compose + osmdroid.

**Spec:** `docs/plans/2026-07-18-map-views-rust-port-design.md`

## Global Constraints

- **Never run `cargo fmt`** in `rust/cw-core` (hand-formatted; gate is build + clippy + test).
- cw-store ids are **lowercase**; never feed Swift `.uuidString` (uppercase) into FFI ids.
- iOS compile-check: `xc` skill with destination `generic/platform=iOS`. **Never** launch the Simulator or UI tests.
- Rust gates: `cargo build` → `cargo clippy` → `cargo test` from `rust/cw-core/`.
- Android build: `JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home ./gradlew :app:assembleDebug` from `android/` (regenerates `uniffi/cw_ffi/cw_ffi.kt` via `buildRustCore`). Grep output for `BUILD SUCCESSFUL` — don't trust wrapper exit codes.
- iOS FFI restage: `./scripts/build-xcframework.sh` from `rust/cw-core/` after any cw-ffi signature change, **before** building iOS.
- swiftformat → swiftlint before any iOS commit (lint errors block hooks).
- Band display order (verbatim, from `MapDataLoadingActor`): `160M, 80M, 60M, 40M, 30M, 20M, 17M, 15M, 12M, 10M, 6M, 2M, 70CM`; excluded bands `EVENT`, `UNKNOWN`.
- QSO display cap when not "show all": **500** (`MapFilterState.maxQSOsDefault`).
- Globe-view span threshold: **90°**; camera padding **1.3** (or **1.5** when lon span > 90), min span 5°, caps 180°/360°.
- Query DSL keys available: `band:`, `mode:`, `park:`, `after:YYYY-MM-DD`, `before:YYYY-MM-DD` (`cw-domain/src/query/token.rs:37-55`, `parser.rs:401-433`). `confirmed_only` is passed as a separate SQL bool, NOT via DSL.
- Commit after every task; include CAR issue id if one is filed for this work.

---

### Task 1: `cw-domain` great-circle segments with antimeridian splitting

**Files:**
- Create: `rust/cw-core/cw-domain/src/great_circle.rs`
- Modify: `rust/cw-core/cw-domain/src/lib.rs` (add `pub mod great_circle;` in alphabetical position)
- Test: inline `#[cfg(test)] mod tests` in the new file

**Interfaces:**
- Consumes: `crate::azimuthal::AzimuthalProjection::great_circle_path(from_lat, from_lon, to_lat, to_lon, segments) -> Vec<(f64, f64)>` (exists, `azimuthal.rs:124`)
- Produces: `great_circle_segments(from: (f64, f64), to: (f64, f64), segments: usize) -> Vec<Vec<(f64, f64)>>` — one or more (lat, lon) polylines, none crossing ±180°. Used by Task 5.

- [ ] **Step 1: Write the failing tests**

```rust
// at bottom of rust/cw-core/cw-domain/src/great_circle.rs (write module skeleton + tests first)
#[cfg(test)]
mod tests {
    use super::*;

    // CM87 (San Francisco ~37.4,-122.3) → PM95 (Tokyo ~35.5,139.4): the great
    // circle goes over the North Pacific and crosses the antimeridian.
    #[test]
    fn splits_pacific_path_at_antimeridian() {
        let segs = great_circle_segments((37.4, -122.3), (35.5, 139.4), 50);
        assert_eq!(segs.len(), 2);
        let first = &segs[0];
        let second = &segs[1];
        // First segment ends exactly on the -180 edge (heading west from -122).
        assert!((first.last().unwrap().1.abs() - 180.0).abs() < 1e-9);
        // Second segment starts on the opposite edge with the same latitude.
        assert!((second[0].1.abs() - 180.0).abs() < 1e-9);
        assert!((first.last().unwrap().0 - second[0].0).abs() < 1e-9);
        assert_ne!(first.last().unwrap().1, second[0].1);
    }

    #[test]
    fn short_path_is_single_segment() {
        let segs = great_circle_segments((32.9, -96.8), (33.9, -96.8), 50);
        assert_eq!(segs.len(), 1);
        assert_eq!(segs[0].len(), 51); // segments + 1 points
    }

    #[test]
    fn zero_distance_returns_two_points() {
        let segs = great_circle_segments((32.9, -96.8), (32.9, -96.8), 50);
        assert_eq!(segs.len(), 1);
        assert_eq!(segs[0].len(), 2);
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cargo test -p cw-domain great_circle` (from `rust/cw-core/`)
Expected: compile error — `great_circle_segments` not defined.

- [ ] **Step 3: Implement**

```rust
//! Great-circle (geodesic) path generation split at the antimeridian.
//!
//! Port of iOS `ActivationMapHelpers.geodesicSegments` /
//! `splitAtAntimeridian` / `interpolateCrossingLat`, reusing the slerp path
//! from `azimuthal::AzimuthalProjection::great_circle_path` so the repo has
//! exactly one great-circle implementation.

use crate::azimuthal::AzimuthalProjection;

/// Generate a geodesic path from `from` to `to` (both `(lat_deg, lon_deg)`),
/// split into segments at ±180° crossings. Each inner Vec is a continuous
/// polyline that does not cross the antimeridian.
pub fn great_circle_segments(
    from: (f64, f64),
    to: (f64, f64),
    segments: usize,
) -> Vec<Vec<(f64, f64)>> {
    let raw = AzimuthalProjection::great_circle_path(from.0, from.1, to.0, to.1, segments);
    split_at_antimeridian(&raw)
}

/// Split a (lat, lon) path at antimeridian crossings, interpolating the
/// crossing latitude so each segment ends/starts exactly on the ±180° edge.
pub fn split_at_antimeridian(path: &[(f64, f64)]) -> Vec<Vec<(f64, f64)>> {
    if path.len() < 2 {
        return vec![path.to_vec()];
    }
    let mut out = Vec::new();
    let mut current = vec![path[0]];
    for i in 1..path.len() {
        let prev = path[i - 1];
        let curr = path[i];
        // A longitude jump > 180° means we crossed the antimeridian.
        if (curr.1 - prev.1).abs() > 180.0 {
            let cross_lat = interpolate_crossing_lat(prev, curr);
            let edge_lon = if prev.1 > 0.0 { 180.0 } else { -180.0 };
            current.push((cross_lat, edge_lon));
            out.push(current);
            current = vec![(cross_lat, -edge_lon)];
        }
        current.push(curr);
    }
    out.push(current);
    out
}

/// Linearly interpolate the latitude at the antimeridian crossing between
/// two points that straddle it.
fn interpolate_crossing_lat(a: (f64, f64), b: (f64, f64)) -> f64 {
    let (lat_a, lon_a) = a;
    let (lat_b, lon_b) = b;
    // Unwrap lon_b onto lon_a's side for interpolation.
    let unwrapped_b = if lon_b - lon_a > 180.0 {
        lon_b - 360.0
    } else if lon_a - lon_b > 180.0 {
        lon_b + 360.0
    } else {
        lon_b
    };
    let target = if lon_a > 0.0 { 180.0 } else { -180.0 };
    let frac = (target - lon_a) / (unwrapped_b - lon_a);
    lat_a + frac * (lat_b - lat_a)
}
```

Register in `lib.rs`: add `pub mod great_circle;` (keep the existing alphabetical module ordering).

- [ ] **Step 4: Run tests to verify they pass**

Run: `cargo test -p cw-domain great_circle`
Expected: 3 passed.

- [ ] **Step 5: Commit**

```bash
git add rust/cw-core/cw-domain/src/great_circle.rs rust/cw-core/cw-domain/src/lib.rs
git commit -m "rust: great-circle segments with antimeridian splitting (map port phase A)"
```

---

### Task 2: `cw-domain` dateline-aware map bounds

**Files:**
- Create: `rust/cw-core/cw-domain/src/map_bounds.rs`
- Modify: `rust/cw-core/cw-domain/src/lib.rs` (add `pub mod map_bounds;`)
- Test: inline `#[cfg(test)] mod tests`

**Interfaces:**
- Produces (used by Task 5):
  - `pub struct MapBounds { pub center_lat: f64, pub center_lon: f64, pub lat_span: f64, pub lon_span: f64 }`
  - `bounds_for(coords: &[(f64, f64)]) -> Option<MapBounds>`
  - `requires_globe_view(b: &MapBounds) -> bool`
  - `camera_spans(b: &MapBounds) -> (f64, f64)` — padded `(lat_span, lon_span)`

- [ ] **Step 1: Write the failing tests**

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn simple_bounds() {
        let b = bounds_for(&[(30.0, -100.0), (40.0, -90.0)]).unwrap();
        assert!((b.center_lat - 35.0).abs() < 1e-9);
        assert!((b.center_lon - -95.0).abs() < 1e-9);
        assert!((b.lat_span - 10.0).abs() < 1e-9);
        assert!((b.lon_span - 10.0).abs() < 1e-9);
    }

    // Points at 170° and -170°: crossing the dateline gives a 20° span
    // centered on ±180, not a 340° span centered on 0.
    #[test]
    fn dateline_crossing_prefers_short_span() {
        let b = bounds_for(&[(10.0, 170.0), (20.0, -170.0)]).unwrap();
        assert!((b.lon_span - 20.0).abs() < 1e-9);
        assert!(b.center_lon.abs() >= 179.999 || (b.center_lon - -180.0).abs() < 1e-9);
    }

    #[test]
    fn empty_is_none() {
        assert!(bounds_for(&[]).is_none());
    }

    #[test]
    fn globe_threshold_is_90() {
        let narrow = MapBounds { center_lat: 0.0, center_lon: 0.0, lat_span: 89.0, lon_span: 10.0 };
        let wide = MapBounds { center_lat: 0.0, center_lon: 0.0, lat_span: 10.0, lon_span: 91.0 };
        assert!(!requires_globe_view(&narrow));
        assert!(requires_globe_view(&wide));
    }

    // padding 1.3 normally, 1.5 when lon_span > 90; min span 5, caps 180/360.
    #[test]
    fn camera_spans_padding() {
        let b = MapBounds { center_lat: 0.0, center_lon: 0.0, lat_span: 2.0, lon_span: 100.0 };
        let (lat, lon) = camera_spans(&b);
        assert!((lat - 5.0 * 1.5).abs() < 1e-9); // max(2,5)=5, wide padding
        assert!((lon - 100.0 * 1.5).abs() < 1e-9);
        let small = MapBounds { center_lat: 0.0, center_lon: 0.0, lat_span: 20.0, lon_span: 30.0 };
        let (lat2, lon2) = camera_spans(&small);
        assert!((lat2 - 26.0).abs() < 1e-9);
        assert!((lon2 - 39.0).abs() < 1e-9);
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cargo test -p cw-domain map_bounds`
Expected: compile error.

- [ ] **Step 3: Implement**

```rust
//! Dateline-aware map bounds/camera math. Port of iOS
//! `ActivationMapHelpers.coordinateBounds` / `mapCameraPosition` /
//! `requiresGlobeView`.

/// Bounding region for a set of coordinates. `lon_span` is the minimal
/// angular span (may cross the antimeridian, in which case `center_lon`
/// is near ±180).
#[derive(Debug, Clone, PartialEq)]
pub struct MapBounds {
    pub center_lat: f64,
    pub center_lon: f64,
    pub lat_span: f64,
    pub lon_span: f64,
}

/// Spans larger than this use a globe camera on platforms that support it.
pub const GLOBE_THRESHOLD_DEG: f64 = 90.0;

pub fn bounds_for(coords: &[(f64, f64)]) -> Option<MapBounds> {
    if coords.is_empty() {
        return None;
    }
    let min_lat = coords.iter().map(|c| c.0).fold(f64::INFINITY, f64::min);
    let max_lat = coords.iter().map(|c| c.0).fold(f64::NEG_INFINITY, f64::max);
    let min_lon = coords.iter().map(|c| c.1).fold(f64::INFINITY, f64::min);
    let max_lon = coords.iter().map(|c| c.1).fold(f64::NEG_INFINITY, f64::max);

    let lat_span = max_lat - min_lat;
    let center_lat = (min_lat + max_lat) / 2.0;

    let direct = max_lon - min_lon;
    let across = 360.0 - direct;
    let (lon_span, center_lon) = if across < direct {
        // Shorter to cross the dateline.
        let raw = max_lon + across / 2.0;
        (across, if raw > 180.0 { raw - 360.0 } else { raw })
    } else {
        (direct, (min_lon + max_lon) / 2.0)
    };

    Some(MapBounds { center_lat, center_lon, lat_span, lon_span })
}

pub fn requires_globe_view(b: &MapBounds) -> bool {
    b.lat_span.max(b.lon_span) > GLOBE_THRESHOLD_DEG
}

/// Padded camera spans: generous padding for wide views so endpoints are
/// not clipped; minimum 5° span; capped at 180°/360°.
pub fn camera_spans(b: &MapBounds) -> (f64, f64) {
    let padding = if b.lon_span > GLOBE_THRESHOLD_DEG { 1.5 } else { 1.3 };
    let lat = (b.lat_span.max(5.0) * padding).min(180.0);
    let lon = (b.lon_span.max(5.0) * padding).min(360.0);
    (lat, lon)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cargo test -p cw-domain map_bounds`
Expected: 5 passed.

- [ ] **Step 5: Commit**

```bash
git add rust/cw-core/cw-domain/src/map_bounds.rs rust/cw-core/cw-domain/src/lib.rs
git commit -m "rust: dateline-aware map bounds + camera spans (map port phase A)"
```

---

### Task 3: `cw-store` map source rows + filter options

**Files:**
- Create: `rust/cw-core/cw-store/src/map_data.rs`
- Modify: `rust/cw-core/cw-store/src/lib.rs` (declare `mod map_data;` and `pub use` its types, matching how `analytics.rs` types are re-exported)
- Test: inline `#[cfg(test)] mod tests` using the same in-memory-store helper the analytics tests use (see `analytics.rs` test module ~line 2700 for the fixture pattern — reuse its `store()`/insert helpers)

**Interfaces:**
- Consumes: `ParsedQuery` + `compile_where(query) -> (String, Vec<Value>)` exactly as `qso_grid_tiles` does (`analytics.rs:726-762`), and the `VISIBLE_QSO` SQL fragment.
- Produces (used by Task 5):

```rust
pub struct MapQsoRow {
    pub id: String,
    pub callsign: String,
    pub band: Option<String>,
    pub mode: Option<String>,
    pub qso_date: i64,            // unix seconds UTC
    pub my_grid: Option<String>,
    pub their_grid: String,       // guaranteed non-empty by the WHERE
    pub park: Option<String>,
    pub state: Option<String>,
    pub dxcc: Option<i64>,
    pub qrz_confirmed: bool,
    pub lotw_confirmed: bool,
    pub power: Option<i64>,
    pub logging_session_id: Option<String>,
    pub my_rig: Option<String>,
}

pub struct MapFilterOptions {
    pub bands: Vec<String>,       // display order, EVENT/UNKNOWN excluded
    pub modes: Vec<String>,       // sorted, metadata modes excluded
    pub parks: Vec<String>,       // sorted
    pub earliest: Option<i64>,
    pub total: i64,               // all visible QSOs (unfiltered)
}
```

  - `pub fn qso_map_rows(&self, query: &ParsedQuery, confirmed_only: bool, limit: Option<i64>) -> Result<Vec<MapQsoRow>>` — visible QSOs with a non-empty `their_grid`, newest first.
  - `pub fn qso_map_filter_options(&self) -> Result<MapFilterOptions>`

- [ ] **Step 1: Write the failing tests**

Follow the analytics test fixture pattern (in-memory store, insert QSOs with band/mode/grids/dates). Test cases:

```rust
#[cfg(test)]
mod tests {
    // reuse the analytics-test store fixture helpers
    #[test]
    fn map_rows_require_their_grid_and_sort_desc() {
        // insert 3 QSOs: one without their_grid, two with (different qso_date)
        // expect 2 rows, newest first, their_grid non-empty
    }

    #[test]
    fn map_rows_confirmed_only_filters() {
        // insert 1 confirmed (lotw) + 1 unconfirmed; confirmed_only=true → 1 row
    }

    #[test]
    fn map_rows_respect_query_and_limit() {
        // insert 20m + 40m QSOs; query "band:20m" returns only 20m;
        // limit Some(1) returns 1
    }

    #[test]
    fn filter_options_ordering_and_exclusions() {
        // insert bands 40M, 20M, EVENT and modes CW, SSB; expect
        // bands == ["40M", "20M"] (band display order), EVENT excluded,
        // modes sorted, earliest == min qso_date, total == visible count
    }
}
```

Write these as real tests with the fixture helpers (copy the insert style from `grid_tiles_group_by_prefix_with_confirmed_and_last`, `analytics.rs:2704`).

- [ ] **Step 2: Run tests to verify they fail**

Run: `cargo test -p cw-store map_data`
Expected: compile error.

- [ ] **Step 3: Implement**

`qso_map_rows` SQL (parameter order: compiled WHERE values, then optional limit):

```sql
SELECT id, callsign, band, mode, qso_date, my_grid, their_grid, park, state,
       dxcc, qrz_confirmed, lotw_confirmed, power, logging_session_id, my_rig
FROM qso
WHERE {VISIBLE_QSO}
  AND their_grid IS NOT NULL AND their_grid != ''
  AND ({where_sql})
  [AND (qrz_confirmed = 1 OR lotw_confirmed = 1)]   -- only when confirmed_only
ORDER BY qso_date DESC
[LIMIT ?]                                            -- only when limit.is_some()
```

`qso_map_filter_options`: three small queries over `WHERE {VISIBLE_QSO}`:
- `SELECT DISTINCT UPPER(band) FROM qso WHERE {VISIBLE_QSO} AND band IS NOT NULL` → drop `EVENT`/`UNKNOWN`, sort by the band display order (index in the constant list, unknowns last alphabetically). Define the order constant in this file:
  ```rust
  const BAND_ORDER: [&str; 13] = ["160M", "80M", "60M", "40M", "30M", "20M",
      "17M", "15M", "12M", "10M", "6M", "2M", "70CM"];
  ```
- `SELECT DISTINCT UPPER(mode) FROM qso WHERE {VISIBLE_QSO} AND mode IS NOT NULL` → exclude metadata modes (reuse the same metadata-mode exclusion the analytics/hunter code uses — grep cw-domain for the existing `is_metadata`-style mode helper and call it; do NOT invent a new list), sort ascending.
- `SELECT DISTINCT park FROM qso WHERE {VISIBLE_QSO} AND park IS NOT NULL` → sort ascending.
- `SELECT MIN(qso_date), COUNT(*) FROM qso WHERE {VISIBLE_QSO}` → earliest/total.

Follow the `prepare`/`query_map`/`collect` style of `qso_grid_tiles` exactly (boxed params, `refs` slice).

- [ ] **Step 4: Run tests to verify they pass**

Run: `cargo test -p cw-store map_data`
Expected: all passed.

- [ ] **Step 5: Commit**

```bash
git add rust/cw-core/cw-store/src/map_data.rs rust/cw-core/cw-store/src/lib.rs
git commit -m "rust: cw-store map source rows + filter options (map port phase A)"
```

---

### Task 4: `cw-ffi` map records + filter → DSL query builder

**Files:**
- Create: `rust/cw-core/cw-ffi/src/map_api/mod.rs`
- Create: `rust/cw-core/cw-ffi/src/map_api/records.rs`
- Create: `rust/cw-core/cw-ffi/src/map_api/filter.rs`
- Modify: `rust/cw-core/cw-ffi/src/lib.rs` — add, with a doc comment matching the style of the other `mod` declarations (see `lib.rs:135-165`):
  ```rust
  /// Shared map view-model: QSO map annotations/clusters/arcs/bounds/stats
  /// plus free geo helpers (great-circle segments, map bounds, tile bounds).
  mod map_api;
  ```
- Test: inline tests in `filter.rs`

**Interfaces:**
- Consumes: `FfiCoordinate` (exists at `lib.rs:428`), `cw_domain::{great_circle, map_bounds, maidenhead}`, Task 3 types.
- Produces the uniffi records used by Tasks 5–8 (`records.rs`, all `#[derive(uniffi::Record)]`):

```rust
pub struct FfiMapFilter {
    pub band: Option<String>,
    pub mode: Option<String>,
    pub park: Option<String>,
    pub start_date: Option<i64>,   // unix seconds UTC, day granularity
    pub end_date: Option<i64>,
    pub confirmed_only: bool,
    pub show_individual: bool,     // per-QSO pins instead of grid clusters
    pub show_paths: bool,          // build arcs
    pub max_qsos: Option<u32>,     // None = show all; Some(500) default cap
}

pub struct FfiQsoMapAnnotation {
    pub id: String,                // qso id (individual) or grid key (cluster)
    pub latitude: f64,
    pub longitude: f64,
    pub grid_square: String,       // 4-char uppercase
    pub qso_count: i64,
    pub callsigns: Vec<String>,    // sorted
    pub most_recent: i64,          // unix seconds
    pub park_references: Vec<String>, // sorted
    pub weather: Option<String>,
    pub solar_conditions: Option<String>,
    pub average_wpm: Option<i64>,
    pub radio: Option<String>,
    pub antenna: Option<String>,
    pub key: Option<String>,
    pub mic: Option<String>,
}

pub struct FfiMapPolyline { pub points: Vec<FfiCoordinate> }

pub struct FfiMapArc {
    pub id: String,                // qso id
    pub callsign: String,
    pub segments: Vec<FfiMapPolyline>,
}

pub struct FfiMapBounds {
    pub center_lat: f64,
    pub center_lon: f64,
    pub lat_span: f64,
    pub lon_span: f64,
    pub camera_lat_span: f64,      // padded, min 5°, capped
    pub camera_lon_span: f64,
    pub requires_globe_view: bool,
}

pub struct FfiMapStats {
    pub duration_seconds: Option<i64>,
    pub qso_rate: Option<f64>,     // QSOs/hour
    pub average_distance_km: Option<f64>,
    pub longest_distance_km: Option<f64>,
    pub watts_per_mile: Option<f64>,
    pub unique_states: i64,
    pub unique_dxcc: i64,
}

pub struct FfiGridBounds {        // for Android grid-overlay polygons
    pub south: f64, pub west: f64, pub north: f64, pub east: f64,
}

pub struct FfiQsoMapData {
    pub annotations: Vec<FfiQsoMapAnnotation>,
    pub arcs: Vec<FfiMapArc>,
    pub bounds: Option<FfiMapBounds>,
    pub stats: FfiMapStats,
    pub filtered_count: i64,       // rows matching filter (pre-cap)
    pub displayed_count: i64,      // rows after cap
    pub is_limited: bool,
    pub total_count: i64,          // all visible QSOs
    pub available_bands: Vec<String>,
    pub available_modes: Vec<String>,
    pub available_parks: Vec<String>,
    pub earliest_date: Option<i64>,
}
```

- `filter.rs` produces: `pub(crate) fn filter_query_string(f: &FfiMapFilter) -> String` — builds a DSL query from the structured filter (band/mode/park/after/before only; `confirmed_only` is NOT in the string).

- [ ] **Step 1: Write the failing tests for the query builder**

```rust
// in filter.rs
#[cfg(test)]
mod tests {
    use super::*;
    use crate::map_api::records::FfiMapFilter;

    fn base() -> FfiMapFilter {
        FfiMapFilter {
            band: None, mode: None, park: None, start_date: None, end_date: None,
            confirmed_only: false, show_individual: false, show_paths: false,
            max_qsos: Some(500),
        }
    }

    #[test]
    fn empty_filter_is_empty_query() {
        assert_eq!(filter_query_string(&base()), "");
    }

    #[test]
    fn full_filter_builds_dsl() {
        let f = FfiMapFilter {
            band: Some("20m".into()),
            mode: Some("CW".into()),
            park: Some("US-0001".into()),
            start_date: Some(1_767_225_600), // 2026-01-01 UTC
            end_date: Some(1_769_904_000),   // 2026-02-01 UTC
            ..base()
        };
        assert_eq!(
            filter_query_string(&f),
            "band:20m mode:CW park:US-0001 after:2026-01-01 before:2026-02-01"
        );
    }

    // The built string must round-trip through the real DSL parser.
    #[test]
    fn built_query_parses() {
        let f = FfiMapFilter { band: Some("40m".into()), ..base() };
        assert!(cw_domain::query::parse(&filter_query_string(&f)).is_ok());
    }
}
```

(Verify the actual `parse` entry-point name/path by looking at how `fetch_qsos_query` in `lib.rs:1750` parses its query string, and use the same call.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `cargo test -p cw-ffi map_api`
Expected: compile error.

- [ ] **Step 3: Implement records.rs, filter.rs, and an empty mod.rs**

`filter.rs`:

```rust
use chrono::{TimeZone, Utc};

use super::records::FfiMapFilter;

/// Build a logbook-DSL query string from the structured map filter.
/// `confirmed_only` intentionally excluded — it is applied as SQL by
/// `qso_map_rows`, not via the DSL.
pub(crate) fn filter_query_string(f: &FfiMapFilter) -> String {
    let mut parts: Vec<String> = Vec::new();
    if let Some(band) = &f.band {
        parts.push(format!("band:{band}"));
    }
    if let Some(mode) = &f.mode {
        parts.push(format!("mode:{mode}"));
    }
    if let Some(park) = &f.park {
        parts.push(format!("park:{park}"));
    }
    if let Some(start) = f.start_date {
        parts.push(format!("after:{}", day_string(start)));
    }
    if let Some(end) = f.end_date {
        parts.push(format!("before:{}", day_string(end)));
    }
    parts.join(" ")
}

fn day_string(unix: i64) -> String {
    Utc.timestamp_opt(unix, 0)
        .single()
        .map(|dt| dt.format("%Y-%m-%d").to_string())
        .unwrap_or_default()
}
```

`mod.rs` for now:

```rust
mod filter;
mod records;

pub use records::*;
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cargo test -p cw-ffi map_api`
Expected: all passed. Also run `cargo clippy -p cw-ffi` — clean.

- [ ] **Step 5: Commit**

```bash
git add rust/cw-core/cw-ffi/src/map_api rust/cw-core/cw-ffi/src/lib.rs
git commit -m "rust: MapApi records + filter→DSL builder (map port phase A)"
```

---

### Task 5: `MapApi.qso_map` aggregation + free geo exports

**Files:**
- Create: `rust/cw-core/cw-ffi/src/map_api/aggregate.rs`
- Modify: `rust/cw-core/cw-ffi/src/map_api/mod.rs` (MapApi object + free exports)
- Test: inline tests in `aggregate.rs` (pure functions, no store needed) plus one store-backed integration test in `mod.rs`

**Interfaces:**
- Consumes: `MapQsoRow`, `MapFilterOptions` (Task 3); `great_circle_segments`, `bounds_for`/`camera_spans`/`requires_globe_view` (Tasks 1–2); `maidenhead::{coordinate_from_grid, distance_km, tile_bounds}`; store activation metadata (`fetch_activation_metadatas`, `cw-store/src/activation_metadata.rs:209`) and logging-session equipment (grep `cw-store/src/logging_session.rs` for the session fetch used by other APIs and reuse it).
- Produces (exported to both platforms):
  - `MapApi.qso_map(filter: FfiMapFilter) -> Result<FfiQsoMapData, CwError>`
  - free fn `great_circle_arc(from: FfiCoordinate, to: FfiCoordinate, segments: u32) -> Vec<FfiMapPolyline>`
  - free fn `map_bounds_for(coords: Vec<FfiCoordinate>) -> Option<FfiMapBounds>`
  - free fn `maidenhead_tile_bounds(tile: String) -> Option<FfiGridBounds>`
  - free fn `compute_map_statistics(rows: Vec<FfiMapStatInput>) -> FfiMapStats` where
    ```rust
    #[derive(uniffi::Record)]
    pub struct FfiMapStatInput {
        pub my_grid: Option<String>,
        pub their_grid: Option<String>,
        pub qso_date: i64,
        pub power: Option<i64>,
        pub logging_session_id: Option<String>,
        pub state: Option<String>,
        pub dxcc: Option<i64>,
    }
    ```
    (this is what iOS `ActivationStatsHelper` switches to in Task 7)

**Aggregation semantics (parity with the deleted Swift, port exactly):**
- **Clusters** (`show_individual == false`): group rows by `their_grid[..4].to_uppercase()`, skipping rows whose grid is shorter than 4. Annotation: coordinate = `coordinate_from_grid(grid_key)` center; `callsigns` = all callsigns sorted (duplicates preserved — Swift used `map`, not a set); `qso_count` = row count; `most_recent` = max qso_date; metadata resolved per the rule below.
- **Individual** (`show_individual == true`): one annotation per row with grid ≥ 4 chars; id = qso id; coordinate from the full grid; count 1.
- **Metadata resolution** (port of `resolveMetadata`, `QSOMapView+Data.swift:93-144`): for each row with a park, key = `"{park}|{yyyy-mm-dd of qso_date UTC}"`; look up activation metadata (weather/solar/WPM) and session equipment (antenna/key/mic) by that key; first non-empty value wins for weather/solar/antenna/key/mic; WPM averages across matches; radio = first non-null `my_rig` among the rows. Build the metadata index once per `qso_map` call: activation metadata joined with session equipment from sessions that have `park_reference`/`sota_reference` and any of antenna/key/mic set, keyed the same way (port of `fetchActivationMetadata`/`fetchSessionEquipment`, `MapDataLoadingActor.swift:330-392`).
- **Arcs** (`show_paths == true` only): one per displayed row having both grids resolvable via `coordinate_from_grid`; id = qso id; segments = `great_circle_segments(from, to, 30)`.
- **Cap**: `displayed = filtered[..max_qsos]` when `max_qsos` is Some; `is_limited = filtered_count > cap`. Annotations/arcs from displayed rows; stats/unique-counts from ALL filtered rows (Swift behavior).
- **Stats** (port of `computeStatistics`, `QSOMapView+Data.swift:266-344`): duration = sum over logging-session groups of (max − min qso_date), `None` if ≤ 1 row or 0; rate = count / (duration/3600); distances via `maidenhead::distance_km(my_grid, their_grid)` per row having both; avg/max; watts-per-mile = avg(power) / avg(distance_miles) over rows having power AND distance (`km × 0.621371`); `unique_states` = distinct valid US states (reuse the same normalized-state validation the WAS analytics use — grep `analytics.rs` for `NORMALIZED_STATE`/valid-state list and reuse, do not invent); `unique_dxcc` = distinct non-null dxcc.
- **Bounds**: from all displayed annotation coordinates + arc endpoints' home coordinate; `None` if empty.

- [ ] **Step 1: Write failing unit tests for the pure aggregation**

```rust
// aggregate.rs tests — construct MapQsoRow values directly.
#[test] fn clusters_group_by_4char_grid_and_sort_callsigns() { /* 3 rows: EM12aa, EM12bb, FN31 → 2 clusters; EM12 cluster count 2, callsigns sorted */ }
#[test] fn individual_skips_short_grids() { /* row with grid "EM" produces no annotation */ }
#[test] fn stats_duration_groups_by_session() { /* 2 sessions of 1h each with gap → duration 7200 */ }
#[test] fn stats_watts_per_mile() { /* known grids + power → expected value (compute expectation by hand from the haversine distance) */ }
#[test] fn arcs_only_with_both_grids() { /* row missing my_grid → no arc */ }
#[test] fn cap_limits_display_not_stats() { /* max_qsos=1 over 3 rows → 1 annotation, filtered_count 3, is_limited true */ }
```

Write these fully (each ~10 lines constructing rows + asserting), then:

- [ ] **Step 2: Run to verify failure**

Run: `cargo test -p cw-ffi map_api`
Expected: compile error.

- [ ] **Step 3: Implement `aggregate.rs` + wire `MapApi` in `mod.rs`**

`mod.rs` additions (follow `session_api.rs:192-202` for the object pattern and `FieldStore` delegation — use the same lock/access helper SessionApi uses):

```rust
use std::sync::Arc;

use crate::{CwError, FieldStore};

#[derive(uniffi::Object)]
pub struct MapApi {
    store: Arc<FieldStore>,
}

#[uniffi::export]
impl MapApi {
    #[uniffi::constructor]
    pub fn new(store: Arc<FieldStore>) -> Arc<Self> {
        Arc::new(Self { store })
    }

    /// One-call QSO map view-model: filtered annotations/arcs/bounds/stats
    /// plus the filter-sheet options. Empty store → empty data, no error.
    pub fn qso_map(&self, filter: FfiMapFilter) -> Result<FfiQsoMapData, CwError> {
        // 1. parse filter_query_string(&filter) with the same parse call
        //    fetch_qsos_query uses (map parse errors to CwError the same way)
        // 2. rows = store.qso_map_rows(&parsed, filter.confirmed_only, None)
        // 3. opts = store.qso_map_filter_options()
        // 4. metadata index from fetch_activation_metadatas + session equipment
        // 5. aggregate::build(rows, opts, meta, &filter)
    }
}

#[uniffi::export]
pub fn great_circle_arc(from: FfiCoordinate, to: FfiCoordinate, segments: u32) -> Vec<FfiMapPolyline> { ... }

#[uniffi::export]
pub fn map_bounds_for(coords: Vec<FfiCoordinate>) -> Option<FfiMapBounds> { ... }

#[uniffi::export]
pub fn maidenhead_tile_bounds(tile: String) -> Option<FfiGridBounds> {
    // cw_domain::maidenhead::tile_bounds (maidenhead.rs:133)
}

#[uniffi::export]
pub fn compute_map_statistics(rows: Vec<FfiMapStatInput>) -> FfiMapStats { ... }
```

`aggregate.rs` implements the semantics block above as pure functions:
`build(rows, opts, meta, filter) -> FfiQsoMapData`, `cluster_annotations`, `individual_annotations`, `build_arcs`, `compute_stats`, `resolve_metadata`. Keep each under ~60 lines.

- [ ] **Step 4: Add one store-backed integration test in `mod.rs`**

```rust
#[test]
fn qso_map_end_to_end() {
    // in-memory FieldStore fixture (reuse the pattern from lib.rs's
    // fetch_qsos_query_filters_by_dsl test, lib.rs:2178):
    // insert 2 QSOs in EM12/PM95 with my_grid CM87, band 20m;
    // qso_map(band 20m, show_paths=true) →
    //   2 annotations (clustered), 2 arcs, bounds.is_some(),
    //   available_bands == ["20M"], total_count == 2
}
```

- [ ] **Step 5: Run full Rust gates**

Run: `cargo build && cargo clippy --all-targets && cargo test -p cw-ffi -p cw-store -p cw-domain`
Expected: clean build, clippy no warnings, all tests pass.

- [ ] **Step 6: Commit**

```bash
git add rust/cw-core/cw-ffi/src/map_api
git commit -m "rust: MapApi.qso_map aggregation + free geo exports (map port phase A)"
```

---

### Task 6: Regenerate FFI artifacts for both platforms

**Files:**
- Regenerated: `swift/ios/.../Vendored/CwFfi.xcframework` (via script), `android/app/src/main/java/uniffi/cw_ffi/cw_ffi.kt` (via gradle)

**Interfaces:**
- Produces: Swift symbols `MapApi`, `FfiMapFilter`, `FfiQsoMapData`, `greatCircleArc`, `mapBoundsFor`, `maidenheadTileBounds`, `computeMapStatistics`, `FfiMapStatInput`, `FfiGridBounds`; same in Kotlin (camelCase functions, data classes).

- [ ] **Step 1: Rebuild the xcframework**

Run from `rust/cw-core/`: `./scripts/build-xcframework.sh`
Expected: completes (takes minutes); vendored `CwFfi.xcframework` restaged.

- [ ] **Step 2: Regenerate Kotlin bindings via the Android build**

Run from `android/`:
`JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home ./gradlew :app:assembleDebug`
Expected: log contains `BUILD SUCCESSFUL`; `git status` shows `cw_ffi.kt` regenerated with the new symbols (`grep -c "class MapApi" android/app/src/main/java/uniffi/cw_ffi/cw_ffi.kt` ≥ 1).

- [ ] **Step 3: Commit the regenerated bindings**

```bash
git add android/app/src/main/java/uniffi/cw_ffi/cw_ffi.kt
git commit -m "android: regen cw_ffi bindings with MapApi (map port phase A)"
```

(The xcframework is gitignored — nothing to commit on the iOS side.)

---

### Task 7: iOS clean cutover

**Files:**
- Delete: `swift/ios/CarrierWave/Views/Map/MapDataLoadingActor.swift`
- Delete: `swift/ios/CarrierWave/Views/Map/QSOMapView+Loading.swift`
- Delete: `swift/ios/CarrierWave/Views/Map/GridOverlayDataActor.swift`
- Rewrite: `swift/ios/CarrierWave/Views/Map/QSOMapView+Data.swift` → becomes the thin FFI mapping layer (new name NOT needed; keep the file, replace contents)
- Modify: `swift/ios/CarrierWave/Views/Map/QSOMapView.swift` (state + load functions)
- Modify: `swift/ios/CarrierWave/Views/Map/QSOAnnotation.swift` (`QSOArc` takes a precomputed path)
- Modify: `swift/ios/CarrierWave/Views/POTAActivations/ActivationMapHelpers.swift` (delegate geodesic/bounds/stats to FFI)
- Modify: whatever `GridHeatmapView`/`GridTrackerSummary` call sites referenced `GridOverlayDataActor` (grep `QSOMapView.gridActor` and `GridOverlayDataActor` — rewire to the new loader below)
- Modify: `swift/ios/CarrierWave/Views/FILE_INDEX.md` (remove deleted files, note new roles)

**Interfaces:**
- Consumes (from Task 6 bindings): `MapApi(store:)`, `mapApi.qsoMap(filter:)`, `computeMapStatistics(rows:)`, `greatCircleArc(from:to:segments:)`, `mapBoundsFor(coords:)`; existing `CwStoreProvider.shared.store()` and `RustAnalyticsReadSource(store:).gridTiles(query:precision:)`.
- Produces: same UI models the views already render (`QSOAnnotation`, `QSOArc`, `MapStatistics`, `GridTrackerSummary`) — view files other than those listed must not need changes.

- [ ] **Step 1: Replace `QSOMapView+Data.swift` contents with the FFI mapping layer**

```swift
import CarrierWaveData
import CoreLocation
import Foundation

// MARK: - QSOMapView FFI Data Layer
//
// All filtering/clustering/stats/arc math lives in Rust (MapApi.qso_map).
// This file only translates FFI records into the UI model types.

extension QSOMapView {
    /// Build the FFI filter from current filter state.
    static func ffiFilter(from state: MapFilterState) -> FfiMapFilter {
        FfiMapFilter(
            band: state.selectedBand,
            mode: state.selectedMode,
            park: state.selectedPark,
            startDate: state.startDate.map { Int64($0.timeIntervalSince1970) },
            endDate: state.endDate.map { Int64($0.timeIntervalSince1970) },
            confirmedOnly: state.confirmedOnly,
            showIndividual: state.showIndividualQSOs,
            showPaths: state.showPaths,
            maxQsos: state.showAllQSOs ? nil : UInt32(MapFilterState.maxQSOsDefault)
        )
    }

    static func annotation(from ffi: FfiQsoMapAnnotation) -> QSOAnnotation {
        QSOAnnotation(
            id: ffi.id,
            coordinate: CLLocationCoordinate2D(latitude: ffi.latitude, longitude: ffi.longitude),
            gridSquare: ffi.gridSquare,
            qsoCount: Int(ffi.qsoCount),
            callsigns: ffi.callsigns,
            mostRecentDate: Date(timeIntervalSince1970: TimeInterval(ffi.mostRecent)),
            parkReferences: Set(ffi.parkReferences),
            weather: ffi.weather,
            solarConditions: ffi.solarConditions,
            averageWPM: ffi.averageWpm.map(Int.init),
            radio: ffi.radio,
            antenna: ffi.antenna,
            key: ffi.key,
            mic: ffi.mic
        )
    }

    static func arc(from ffi: FfiMapArc) -> QSOArc {
        QSOArc(
            id: ffi.id,
            callsign: ffi.callsign,
            path: ffi.segments.flatMap { segment in
                segment.points.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                }
            }
        )
    }

    static func statistics(from ffi: FfiMapStats) -> MapStatistics {
        MapStatistics(
            activationDuration: ffi.durationSeconds.map(TimeInterval.init),
            qsoRate: ffi.qsoRate,
            averageDistanceKm: ffi.averageDistanceKm,
            longestDistanceKm: ffi.longestDistanceKm,
            wattsPerMile: ffi.wattsPerMile
        )
    }
}

// MARK: - MapStatistics

/// Computed distance and rate statistics (rendered by MapStatsOverlay).
nonisolated struct MapStatistics {
    static let empty = MapStatistics(
        activationDuration: nil, qsoRate: nil, averageDistanceKm: nil,
        longestDistanceKm: nil, wattsPerMile: nil
    )

    let activationDuration: TimeInterval?
    let qsoRate: Double?
    let averageDistanceKm: Double?
    let longestDistanceKm: Double?
    let wattsPerMile: Double?
}
```

(`ResolvedAnnotationMetadata` and every compute/filter function are deleted with the old contents. If `MapPolyline` rendering wants per-segment polylines instead of the flattened path, keep `QSOArc.path` flattened — that matches current rendering.)

- [ ] **Step 2: Update `QSOArc` in `QSOAnnotation.swift`**

Replace the geodesic-computing `init` and `computeGeodesicPath` with a stored-path init:

```swift
nonisolated struct QSOArc: Identifiable {
    let id: String
    let callsign: String
    /// Pre-computed geodesic path from Rust (antimeridian-split, flattened).
    let path: [CLLocationCoordinate2D]

    init(id: String, callsign: String, path: [CLLocationCoordinate2D]) {
        self.id = id
        self.callsign = callsign
        self.path = path
    }
}
```

Grep for other `QSOArc(` constructions (e.g. `SessionQSOMap`, `MapContentBuilders`) — any caller still passing `from:`/`to:` switches to `greatCircleArc(from:to:segments:)` FFI + the new init. Update those call sites in place.

- [ ] **Step 3: Rewrite the loading path in `QSOMapView.swift`**

Remove `loadingActor`/`gridActor` statics, `allSnapshots`, `cachedMetadataByKey`, `loadingProgress`, and the progress UI in `loadingView` (keep a plain spinner). Add:

```swift
/// Load everything from MapApi in one call.
func reloadFromMapApi() async {
    isLoadingQSOs = cachedAnnotations.isEmpty // spinner only on first load
    do {
        let store = try await CwStoreProvider.shared.store()
        let api = MapApi(store: store)
        let filter = Self.ffiFilter(from: filterState)
        let data = try await Task.detached { try api.qsoMap(filter: filter) }.value

        cachedAnnotations = data.annotations.map(Self.annotation(from:))
        cachedArcs = data.arcs.map(Self.arc(from:))
        cachedStatistics = Self.statistics(from: data.stats)
        cachedUniqueStates = Int(data.stats.uniqueStates)
        cachedUniqueDXCCEntities = Int(data.stats.uniqueDxcc)
        cachedFilteredSnapshotCount = Int(data.filteredCount)
        cachedIsLimited = data.isLimited
        totalQSOCount = Int(data.totalCount)
        cachedAvailableBands = data.availableBands
        cachedAvailableModes = data.availableModes
        cachedAvailableParks = data.availableParks
        cachedEarliestQSODate = data.earliestDate
            .map { Date(timeIntervalSince1970: TimeInterval($0)) }

        if let bounds = data.bounds, !hasLoadedInitialData {
            cameraPosition = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: bounds.centerLat, longitude: bounds.centerLon
                ),
                span: MKCoordinateSpan(
                    latitudeDelta: bounds.cameraLatSpan,
                    longitudeDelta: bounds.cameraLonSpan
                )
            ))
        }
        hasLoadedInitialData = true
    } catch {
        RadioService.shared.addLog("Map load failed: \(error)")
    }
    isLoadingQSOs = false
}
```

Every `.onChange` handler and the `.task` call `reloadFromMapApi()` (the `showAllQSOs` handler no longer needs the reload-flag dance — same call). Grid overlay loading (`loadGridOverlay` / `updateGridOverlay`) moves to the new loader in Step 4.

Note the error path: route through `RadioService.shared.addLog` (never `print`/`os_log` — project logging rule).

- [ ] **Step 4: Replace `GridOverlayDataActor` with a store-only loader**

Delete the file. Create `swift/ios/CarrierWave/Views/Map/GridSummaryLoader.swift`:

```swift
import CarrierWaveCore
import CarrierWaveData
import Foundation

/// Loads the grid tracker summary from cw-store (SQL GROUP BY) — the only
/// grid aggregation path since the SwiftData scan was removed (map port
/// phase A).
enum GridSummaryLoader {
    static func load() async throws -> GridTrackerSummary {
        let store = try await CwStoreProvider.shared.store()
        let tiles = try await RustAnalyticsReadSource(store: store)
            .gridTiles(query: "", precision: 4)

        var gridData: [String: GridSquareData] = [:]
        var fieldCounts: [String: Int] = [:]
        for tile in tiles {
            let status: GridSquareStatus = tile.confirmed > 0
                ? .confirmed(count: tile.confirmed)
                : .worked(count: tile.count)
            gridData[tile.tile] = GridSquareData(
                grid: tile.tile,
                status: status,
                qsoCount: tile.count,
                confirmedCount: tile.confirmed,
                callsigns: tile.callsigns,
                bands: Set(tile.bands),
                modes: Set(tile.modes),
                mostRecent: tile.lastQSO > 0
                    ? Date(timeIntervalSince1970: TimeInterval(tile.lastQSO))
                    : nil
            )
            fieldCounts[String(tile.tile.prefix(2)), default: 0] += 1
        }
        return GridTrackerSummary(
            totalGridsWorked: gridData.count,
            totalGridsConfirmed: gridData.values.filter { $0.confirmedCount > 0 }.count,
            totalFields: fieldCounts.count,
            gridData: gridData,
            fieldCounts: fieldCounts
        )
    }
}
```

Grep all `GridOverlayDataActor` / `QSOMapView.gridActor` call sites (`QSOMapView+Loading.swift` is deleted; expect `GridHeatmapView`/grid tracker + the map's `loadGridOverlay`) and rewire to `GridSummaryLoader.load()` + `GridOverlayRenderer.buildPolygons(from:)`. Match the exact `GridSquareData` initializer signature from its definition (check field order before writing).

- [ ] **Step 5: Swap `ActivationMapHelpers` internals to FFI**

In `ActivationMapHelpers.swift`:
- `geodesicSegments` body becomes a call to `greatCircleArc(from:to:segments:)`, mapping `FfiMapPolyline` → `[[CLLocationCoordinate2D]]`. Delete `rawGeodesicPath`, `splitAtAntimeridian`, `interpolateCrossingLat`.
- `mapRegion` / `mapCameraPosition` / `requiresGlobeView` call `mapBoundsFor(coords:)` and use `cameraLatSpan`/`cameraLonSpan`/`requiresGlobeView` from the record. Delete the private `coordinateBounds` and `CoordinateBounds`. Keep `tightestLongitudeBounds` ONLY if something still calls it (grep; if unused after this change, delete it too).
- `ActivationStatsHelper.statistics(forQSOs:)` builds `[FfiMapStatInput]` from the QSO list and calls `computeMapStatistics(rows:)`, then maps to `MapStatistics` via `QSOMapView.statistics(from:)`. Delete the `MapQSOSnapshot`-based body.

- [ ] **Step 6: Delete the dead files and fix stragglers**

```bash
git rm swift/ios/CarrierWave/Views/Map/MapDataLoadingActor.swift \
       swift/ios/CarrierWave/Views/Map/QSOMapView+Loading.swift \
       swift/ios/CarrierWave/Views/Map/GridOverlayDataActor.swift
```

Grep for now-dangling symbols: `MapQSOSnapshot`, `MapLoadedData`, `MapFilterSnapshot`, `ProcessedMapData`, `MapActivationMetadata`, `MapLoadingProgress`. Any remaining consumer (e.g. `ActivationStatsHelper` before Step 5, share renderers) must be updated or the symbol re-homed — nothing may remain referencing the deleted files. Update `Views/FILE_INDEX.md`.

- [ ] **Step 7: Build + lint**

Run: swiftformat then swiftlint on changed files, then `xc` build with destination `generic/platform=iOS` (from `swift/ios/`).
Expected: build succeeds, no lint errors. Fix iteratively — do not commit red.

- [ ] **Step 8: Commit**

```bash
git add -A swift/ios
git commit -m "ios: QSO map clean cutover to Rust MapApi; delete SwiftData map pipeline (map port phase A)"
```

---

### Task 8: Android Map tab parity

**Files:**
- Modify: `android/app/src/main/java/app/carrierwave/android/CwApp.kt` (add `lateinit var mapApi: MapApi`; init `mapApi = MapApi(store)` next to `sessionApi = SessionApi(store)` at line ~175)
- Rewrite: `android/app/src/main/java/app/carrierwave/android/ui/map/MapViewModel.kt`
- Rewrite: `android/app/src/main/java/app/carrierwave/android/ui/map/MapScreen.kt`
- Create: `android/app/src/main/java/app/carrierwave/android/ui/map/MapFilterSheet.kt`
- Create: `android/app/src/main/java/app/carrierwave/android/ui/map/QsoCalloutCard.kt`

**Interfaces:**
- Consumes: `MapApi.qsoMap(FfiMapFilter)`, `FieldStore.qsoGridTiles(query, precision)` (existing binding — verify exact Kotlin name in `cw_ffi.kt`), `maidenheadTileBounds(tile)`, `maidenheadCoordinate(grid)`, existing `store.dxccWorked("")`.
- Produces: full-parity Map tab. DXCC layer untouched.

- [ ] **Step 1: Rewrite `MapViewModel.kt`**

```kotlin
package app.carrierwave.android.ui.map

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider.AndroidViewModelFactory.Companion.APPLICATION_KEY
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import app.carrierwave.android.CwApp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.cw_ffi.FfiGridBounds
import uniffi.cw_ffi.FfiMapFilter
import uniffi.cw_ffi.FfiQsoMapData
import uniffi.cw_ffi.FieldStore
import uniffi.cw_ffi.MapApi
import uniffi.cw_ffi.MapPin  // NOTE: if the old local MapPin data class is still
                             // used by the DXCC layer keep the local one; do not import
import uniffi.cw_ffi.maidenheadTileBounds

/** Which overlay the map is showing. */
enum class MapLayer { QSOS, DXCC }

/** UI filter state mirrored into FfiMapFilter on each reload. */
data class MapFilter(
    val band: String? = null,
    val mode: String? = null,
    val park: String? = null,
    val startDate: Long? = null,
    val endDate: Long? = null,
    val confirmedOnly: Boolean = false,
    val showIndividual: Boolean = false,
    val showPaths: Boolean = false,
    val showAll: Boolean = false,
    val showGridOverlay: Boolean = false,
) {
    val hasActiveFilters: Boolean
        get() = band != null || mode != null || park != null ||
            startDate != null || endDate != null || confirmedOnly
}

/** One worked-grid overlay tile with its corner bounds and status. */
data class GridOverlayTile(
    val bounds: FfiGridBounds,
    val confirmed: Boolean,
)

data class MapUiState(
    val layer: MapLayer = MapLayer.QSOS,
    val filter: MapFilter = MapFilter(),
    val data: FfiQsoMapData? = null,
    val gridTiles: List<GridOverlayTile> = emptyList(),
    val dxccPins: List<MapPinUi> = emptyList(),
    val loading: Boolean = true,
    val error: String? = null,
)

data class MapPinUi(val latitude: Double, val longitude: Double, val title: String)

/**
 * Map tab — Rust MapApi view-model. All clustering/arc/stat math is shared
 * with iOS via cw-ffi; this class only shuttles state.
 */
class MapViewModel(
    private val mapApi: MapApi,
    private val store: FieldStore,
    val homeGrid: String,
) : ViewModel() {

    private val _state = MutableStateFlow(MapUiState())
    val state: StateFlow<MapUiState> = _state.asStateFlow()

    init {
        reload()
        viewModelScope.launch { loadDxcc() }
    }

    fun setLayer(layer: MapLayer) = _state.update { it.copy(layer = layer) }

    fun updateFilter(transform: (MapFilter) -> MapFilter) {
        val newFilter = transform(_state.value.filter)
        _state.update { it.copy(filter = newFilter) }
        reload()
        if (newFilter.showGridOverlay && _state.value.gridTiles.isEmpty()) {
            viewModelScope.launch { loadGridTiles() }
        }
    }

    fun reload() {
        viewModelScope.launch {
            _state.update { it.copy(loading = it.data == null) }
            val filter = _state.value.filter
            val result = withContext(Dispatchers.IO) {
                runCatching {
                    mapApi.qsoMap(
                        FfiMapFilter(
                            band = filter.band,
                            mode = filter.mode,
                            park = filter.park,
                            startDate = filter.startDate,
                            endDate = filter.endDate,
                            confirmedOnly = filter.confirmedOnly,
                            showIndividual = filter.showIndividual,
                            showPaths = filter.showPaths,
                            maxQsos = if (filter.showAll) null else 500u,
                        )
                    )
                }
            }
            result.fold(
                onSuccess = { data -> _state.update { it.copy(data = data, loading = false, error = null) } },
                onFailure = { e -> _state.update { it.copy(loading = false, error = e.message) } },
            )
        }
    }

    private suspend fun loadGridTiles() {
        val tiles = withContext(Dispatchers.IO) {
            runCatching {
                store.qsoGridTiles("", 4).mapNotNull { tile ->
                    maidenheadTileBounds(tile.tile)?.let { bounds ->
                        GridOverlayTile(bounds, tile.confirmed > 0)
                    }
                }
            }.getOrDefault(emptyList())
        }
        _state.update { it.copy(gridTiles = tiles) }
    }

    private suspend fun loadDxcc() {
        val pins = withContext(Dispatchers.IO) {
            runCatching {
                store.dxccWorked("").map {
                    MapPinUi(it.latitude, it.longitude, "${it.name} · ${it.count}")
                }
            }.getOrDefault(emptyList())
        }
        _state.update { it.copy(dxccPins = pins) }
    }

    companion object {
        fun factory() = viewModelFactory {
            initializer {
                val app = this[APPLICATION_KEY] as CwApp
                MapViewModel(app.mapApi, app.store, app.repository.homeGrid)
            }
        }
    }
}
```

(Verify the exact generated Kotlin method/record names in `cw_ffi.kt` after Task 6 — uniffi lower-camel-cases functions; `qsoGridTiles` signature/precision type must be checked and matched, and drop the bogus `MapPin` import — the pin UI type is `MapPinUi` here.)

- [ ] **Step 2: Rewrite `MapScreen.kt`**

Keep the osmdroid `AndroidView` scaffold and home-grid centering. Changes:
- Layer chips row gains: `Grid` toggle chip (sets `showGridOverlay`), `Arcs` chip (`showPaths`), filter icon button (opens `MapFilterSheet`; badge when `filter.hasActiveFilters`).
- QSOS layer renders `state.data.annotations` as `Marker`s (title = grid + count, or callsign when `qsoCount == 1L`); tap sets a `selectedAnnotation` state rendered as `QsoCalloutCard` at the bottom.
- Arcs: for each `FfiMapArc`, for each `segment`, add an osmdroid `Polyline` with `setPoints(segment.points.map { GeoPoint(it.latitude, it.longitude) })`, width ~3f, white 50% alpha.
- Grid overlay: for each `GridOverlayTile` add an osmdroid `Polygon` with the four corners from `FfiGridBounds` (`GeoPoint(south, west)`, `(south, east)`, `(north, east)`, `(north, west)`), fill green 20% alpha when `confirmed` else blue 15%, stroke 1f.
- Stats strip under the chips: `visible/total QSOs · grids (annotations.size) · states · DXCC`, plus `duration / rate / avg / max / W-per-mile` when non-null (format km with 0 decimals, rate 1 decimal). Show `Limited to 500` caption when `isLimited`.
- Rebuild overlays inside the existing `AndroidView(update = ...)` block by clearing `mapView.overlays` and re-adding per current state (the pattern the file already uses for markers).

- [ ] **Step 3: Create `MapFilterSheet.kt`**

`ModalBottomSheet` with: band `FilterChip` row from `data.availableBands` (single-select, tap again to clear), same for modes and parks (parks in a dropdown if > 8), two `DatePicker` fields for start/end (map to unix seconds UTC midnight), `Switch` for confirmed-only, `Switch` for individual pins, "Reset" button (clears all). Every change funnels through `viewModel.updateFilter { ... }`.

- [ ] **Step 4: Create `QsoCalloutCard.kt`**

Card mirroring iOS `QSOCalloutView` content from `FfiQsoMapAnnotation`: title (`callsign` if single, else `grid (count)`), up-to-3 callsigns + `+N more`, park refs, and when present: weather, solar, avg WPM, radio/antenna/key/mic rows. Dismiss on tap.

- [ ] **Step 5: Build**

Run from `android/`:
`JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home ./gradlew :app:assembleDebug`
Expected: `BUILD SUCCESSFUL` in output. Fix iteratively.

- [ ] **Step 6: Commit**

```bash
git add android
git commit -m "android: Map tab parity via Rust MapApi — clusters, arcs, grid overlay, filters, stats (map port phase A)"
```

---

### Task 9: Changelog + final gates

**Files:**
- Modify: `CHANGELOG.md` (repo root, `[Unreleased]`)

- [ ] **Step 1: Update CHANGELOG under `[Unreleased]`**

```markdown
### Changed
- QSO map view-model (filtering, grid clustering, geodesic arcs, camera
  bounds, statistics) moved to shared Rust (`MapApi`); iOS SwiftData map
  pipeline removed — the map now reads exclusively from the local store.

### Added
- Android: full-parity Map tab — grid clusters with callout details,
  geodesic arc overlays, worked/confirmed grid overlay, filter sheet
  (band/mode/park/date/confirmed), and session statistics.
```

- [ ] **Step 2: Run every gate one final time**

- `cargo build && cargo clippy --all-targets && cargo test` (from `rust/cw-core/`)
- swiftformat + swiftlint + `xc` build `generic/platform=iOS`
- `JAVA_HOME=... ./gradlew :app:assembleDebug` → `BUILD SUCCESSFUL`

Expected: all green. If anything is red, fix before committing.

- [ ] **Step 3: Commit + verify clean tree**

```bash
git add CHANGELOG.md
git commit -m "docs: changelog for map Rust port phase A"
git status
```

Expected: working tree clean.

---

## Post-plan notes for the executor

- **Parity risk flag (accepted in spec):** after Task 7, iOS maps show only cw-store QSOs. If a device-test later shows missing pins, the store delegation — not this code — is the suspect.
- **Device verification is owed** (per project convention) but is NOT part of this plan: deploy to `theseus` and eyeball Map tab, filters, arcs, grid overlay on both platforms when the user asks.
- Phase B (embedded cards) builds directly on the free exports added in Task 5 — don't rename them casually.

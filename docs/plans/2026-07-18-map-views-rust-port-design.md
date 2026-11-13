# Map Views → Shared Rust Port — Design

**Date:** 2026-07-18
**Status:** Approved design; Phase A spec. Phases B–D get their own spec/plan cycles.

## Goal

Port the iOS map views to Android with as much logic as possible in shared Rust
(`cw-domain` / `cw-ffi`), and replace the iOS Swift implementations with the
Rust-backed versions (clean cutover, no SwiftData fallback).

## Scope decisions (settled with Jay 2026-07-18)

- **In scope:** Map tab QSO map, park search map, all embedded map cards.
  Missing Android host screens (propagation check, POTA activation browser,
  brag share cards) get built too.
- **Out of scope:** Azimuthal spot map tab (excluded for now). NEXRAD radar and
  admin/county overlays stay iOS-Swift-only.
- **Rust depth:** full Rust view-model. A new `MapApi` in `cw-ffi` returns
  render-ready data (annotations, clusters, grid tiles, arc polylines, bounds,
  stats). Swift/Kotlin only translate to MapKit/osmdroid primitives.
- **iOS cutover:** clean. Delete the SwiftData map data paths outright; maps
  become FieldStore-authoritative. Known risk: any QSO present in SwiftData but
  missing from cw-store disappears from the map. Accepted.
- **Share renderers:** Rust rasterizes the themed flat/azimuthal share maps to
  PNG bytes (tiny-skia or similar pure-Rust raster dep). Pixel-identical share
  cards on both platforms; ~1,000 lines of CoreGraphics deleted. MapKit-styled
  share variants (adaptive/globe/satellite) stay Swift.
- **API organization:** single `#[uniffi::Object] MapApi` in
  `cw-ffi/src/map_api/` (submodule layout like `spot_engine/`), not methods
  smeared across SessionApi/ReferenceDataApi/BragSheetApi.

## Existing foundation (survey results, 2026-07-18)

- `cw-domain/src/maidenhead.rs` — grid↔coord, distance, bearing, grid bounds,
  grids-in-region. Already FFI-exposed (`maidenheadCoordinate`,
  `maidenheadBearing`).
- `cw-domain/src/azimuthal.rs` — full azimuthal-equidistant projection port of
  `AzimuthalProjection.swift` incl. `great_circle_path` (slerp, no antimeridian
  splitting) and sector binning. **Tested but not FFI-exposed.**
- `cw-domain/src/coastline.rs` — embedded Natural Earth 110m coastlines
  (103 rings). **Not FFI-exposed.**
- `cw-ffi` analytics already computes grid tiles (`RustAnalyticsReadSource.gridTiles`
  consumer on iOS) and spot geo-enrichment (distance/bearing).
- Android already has an osmdroid Map tab (QSO-count-per-grid + DXCC layers,
  `MapScreen.kt`/`MapViewModel.kt`) and `ClubMapView.kt`.
- iOS map surface: ~13,800 lines / 62 files (see survey; `Views/Map/` is
  44 files / 9,241 lines).

## Phasing roadmap

Each phase is its own spec → plan → implement cycle.

- **Phase A (this spec):** MapApi core + QSO map, both platforms.
- **Phase B:** embedded cards on existing hosts — session logger map, session
  detail map card, timeline replay, QSO detail arc, callsign map section,
  spots mini-map, club map (member coordinate lookup moves to Rust:
  QRZ → HamDB fallback + cache in cw-net).
- **Phase C:** park search map — park/summit/WWFF search + boundary/trail
  fetch in Rust (`cw-net`), MultiplierFinder point-in-polygon geometry port;
  new Android park search screen. Radar/admin overlays remain Swift.
- **Phase D:** share renderers (Rust PNG rasterizer for flat + azimuthal
  themes) + new Android hosts (propagation check, activation browser,
  brag share cards).

## Phase A design

### 1. Rust domain (`cw-domain`)

New modules alongside `maidenhead`/`azimuthal`:

- `great_circle.rs` — geodesic path generation **with antimeridian splitting**.
  Consolidates the two duplicate Swift implementations
  (`ActivationMapHelpers.rawGeodesicPath` + antimeridian helpers, and
  `AzimuthalProjection.greatCirclePath`). Output: `Vec<Vec<(f64, f64)>>` —
  one or more polyline segments split at ±180°.
- `map_bounds.rs` — dateline-aware bounding box / tightest-longitude-span math
  (port of `ActivationMapHelpers.coordinateBounds` / `tightestLongitudeBounds`)
  plus a pure `requires_globe_view(span)` predicate.

### 2. Rust FFI (`cw-ffi/src/map_api/`)

`#[derive(uniffi::Object)] MapApi { store: Arc<FieldStore> }`,
`#[uniffi::constructor] new(store)`. Methods:

- `qso_map(filter: FfiMapFilter) -> FfiQsoMapData`
  - `FfiMapFilter`: bands, modes, date range, park ref, confirmed-only.
    Applied in SQL against cw-store, not in-memory.
  - `FfiQsoMapData`:
    - `annotations: Vec<FfiQsoAnnotation>` — individual QSO pins (used below
      cluster threshold): callsign, grid, lat/lon, band, mode, rst, timestamp,
      qso id.
    - `clusters: Vec<FfiGridCluster>` — 4-char-grid clusters: grid, center
      coord, count, confirmed count, callsigns/bands/modes summary, most
      recent timestamp.
    - `arcs: Vec<FfiArc>` — geodesic polyline segments home→contact
      (antimeridian-split), keyed to annotation/cluster.
    - `bounds: FfiMapBounds` — dateline-aware camera bounds +
      `requires_globe_view`.
    - `stats: FfiMapStats` — duration, QSO rate, avg/max distance km,
      watts-per-mile.
- `grid_overlay(bounds: FfiMapBounds, precision) -> Vec<FfiGridTile>` —
  worked/confirmed status per grid tile; builds on the existing gridTiles
  analytics path.
- Free-function exports added for later phases' cards:
  `greatCirclePath(from, to) -> Vec<Vec<FfiCoordinate>>`,
  `mapBounds(coords) -> FfiMapBounds`.

Errors: `qso_map` returns empty data on an empty store; throws `CwException`
only on store failure. All id plumbing via the established lowercase-uuid
helpers (cw-store ids are lowercase; never raw `.uuidString`).

### 3. iOS cutover (clean)

- `QSOMapView` keeps MapKit rendering; consumes `FfiQsoMapData`:
  annotations → `Annotation`/`Marker`, arcs → `MapPolyline`,
  bounds → `MKCoordinateRegion`, tiles → `MapPolygon`.
- **Deleted:** `MapDataLoadingActor` (402 lines), aggregation/filter/stats
  logic in `QSOMapView+Data` (~340 lines), `QSOMapView+Loading`,
  `GridOverlayDataActor` (both paths — collapses to an FFI call).
- **Stays Swift:** color mapping (band/RST → Color), callout views, filter
  sheet UI, camera handling.
- `GridHeatmapView` (grid tracker) moves onto `grid_overlay` output in this
  phase, since its data actor is being deleted.

### 4. Android

- Map tab QSO layer upgraded to parity: clustered + individual markers with
  callout detail, geodesic arc overlays (osmdroid `Polyline`), grid overlay
  (osmdroid `Polygon`), filter sheet (band/mode/date/park/confirmed), stats
  strip.
- New `MapRepository` following `LogbookRepository`'s pattern:
  `withContext(Dispatchers.IO)` around FFI calls, `CwException` → `Result`.
- DXCC layer unchanged (already Rust-backed via `FieldStore.dxccWorked`).

### 5. Testing & quality gates

- Rust unit tests: antimeridian splitting on known crossings (e.g. W6↔JA),
  dateline bounds, cluster aggregation counts/confirmed flags.
- Parity fixtures per the rust-swift-parity rule: known QSO sets asserted to
  produce identical cluster/stat outputs to the current Swift implementation
  (captured before deletion).
- Gates: `cargo build` + clippy + test (no `cargo fmt` in cw-core);
  swiftformat → swiftlint → iOS compile-check (`generic/platform=iOS`);
  Android assembleDebug. xcframework regen via
  `rust/cw-core/scripts/build-xcframework.sh`; Kotlin bindings per the
  android-build-env recipe.

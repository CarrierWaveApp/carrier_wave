# Map Boundary Overlays — Design & Plan

**Date:** 2026-06-03
**Status:** Design approved (per Q&A); implementation sequenced below
**Surface:** `swift/ios/CarrierWave/Views/Map/` (extends the existing **Parks & Summits** reference map)
**Branch:** `claude/map-boundary-overlays-jOWiS`

## Goals

User stories driving this work:

1. **View activation/admin boundaries on a map** — POTA, SOTA, WWFF, US counties, and US
   states — so users can plan field activities that leverage multiple activation types
   (e.g. a POTA + SOTA 2-fer) and multiple counties (e.g. QSO-party county-line multipliers).
2. **(Deferred)** An automatically flagged list of multiplier locations, identified by
   geographic overlap, to help narrow down high-value spots.

Developer asks folded in:

- Add **Maidenhead grid square** and **Tiles-on-the-Air (TOTA) tile** overlays.
- **Every overlay is individually toggleable** so the map is never over-populated.
- Build **service by service**.

## Decisions (from product Q&A)

| Question | Decision |
|----------|----------|
| Map surface | **Extend** the existing `ParkSearchMapView` ("Parks & Summits"), not a new screen |
| Geographic scope | **US-first** (counties/states are US QSO-party concepts) |
| County/state data source | Investigated → **serve via the activities server** (PostGIS + viewport endpoint, mirroring POTA) |
| WWFF boundaries | No polygon source exists → **borrow the POTA polygon** where a `KFF-XXXX ↔ US-XXXX` mapping exists; fall back to a pin |
| SOTA zones | **Do not use activation.zone's API.** Reverse-engineer the technique and **recreate it** from open DEM data |
| Feature gating | **New experiment** (`alpha`), separate from the existing `.parkGIS` |
| Toggle UX | **Expand the existing inline overlay menu** (sectioned), not a new sheet |
| Multiplier list (#2) | **Defer** until the overlays land |
| First build slice | **Client-only wins first** (experiment flag + grid squares + TOTA tiles), then counties/states → SOTA zones → WWFF |

## Existing infrastructure (what we build on)

- **POTA boundaries — already shipped.** Rust activities server stores polygons in PostGIS
  (`park_boundaries` table, PAD-US 4 source, full + simplified geometry, GIST indexes;
  `server/migrations/011_park_boundaries.sql`). Served viewport-first via
  `/v1/parks/boundaries?bbox=west,south,east,north` (`server/src/handlers/park_boundaries.rs`).
  Client: `ActivitiesClient.fetchParkBoundaries(...)` → `ParkBoundary` / `MergedPolygon`
  (`swift/ios/CarrierWave/Models/ParkBoundary.swift`), cached 30 days
  (`ParkBoundaryCache.swift`), rendered by `BoundaryFillOverlay` / `BoundarySkirtOverlay`
  in `ParkSearchMapKit`. **This is the template for counties, states, and SOTA zones.**
- **Reference map** `ParkSearchMapView` already has the overlay toggle menu
  (`slider.horizontal.3`): Boundaries / Trails / Park Pins / Summit Pins, plus per-toggle
  `@State` flags and viewport-culled rendering.
- **WWFF↔POTA mapping** already exists: `ProgramCrossReferenceService` resolves
  `KFF-XXXX ↔ US-XXXX` by number (and by name). Reusable to borrow POTA polygons for WWFF.
- **Grid squares** (`GridOverlayRenderer`, `GridSquareOverlay`) and **TOTA tiles**
  (`MaidenheadConverter.tileBounds(for:)`) are fixed Maidenhead grids computed client-side —
  no data sourcing, no network. Currently used on the QSO map / TOTA session map; reusable here.
- `SOTASummit` and `WWFFReference` are **point + metadata only** (no polygons today).

## Per-service plan

### POTA boundaries (done — wire toggle)
Already rendered. Just ensure it is one toggle in the unified menu, gated as today by
`.parkGIS`. No new work beyond menu grouping.

### Maidenhead grid squares (client-only)
- Reuse `GridOverlayRenderer.gridCorners()` / `GridSquareComputation.visibleGrids()`.
- Render as polylines (no per-grid fill) on `ParkSearchMapKit`.
- **Zoom-gate**: existing `visibleGrids()` already caps at 400 grids / 30°×60° span — reuse it
  to avoid over-population at low zoom.
- Toggle: "Grid Squares" (off by default).

### TOTA tiles (client-only)
- Reuse `MaidenheadConverter.tileBounds(for:)` (6-char subsquares) to draw tile rectangles for
  the visible region.
- 6-char tiles are dense (~3.7 × 4.6 km). **Zoom-gate** to a tighter threshold than grid
  squares (only render when `span.latitudeDelta` below a small cutoff) and cap tile count.
- Toggle: "Tiles on the Air" (off by default).

### US counties & states (server)
- **Data**: US Census cartographic boundary files (simplified; full national county set ≈ 2.2 MB
  at 20 m, states smaller). Import into the existing PostGIS exactly like the PAD-US pipeline.
- **Schema**: new tables `admin_boundaries_county` / `admin_boundaries_state` (or one
  `admin_boundaries` table with a `kind` column) with `geometry` + `geometry_simplified`,
  `name`, `fips`, GIST indexes — mirror `011_park_boundaries.sql`.
- **Endpoints**: `/v1/admin/counties?bbox=...` and `/v1/admin/states?bbox=...` (or a single
  `?bbox=&kind=county|state`), returning GeoJSON FeatureCollections like park boundaries.
- **Client**: extend `ActivitiesClient` with `fetchCountyBoundaries` / `fetchStateBoundaries`,
  add a lightweight cache mirroring `ParkBoundaryCache`, reuse the `MergedPolygon` rendering path
  with distinct stroke colors (no fill, or very light fill) to read as administrative lines.
- **Zoom-gate**: states visible at continental zoom (≈50 polygons, cheap); **counties only when
  zoomed in** (≈3,143 nationally — never load all at once; viewport + zoom threshold).
- Toggles: "Counties", "States".

### WWFF (borrow POTA polygon)
- For each visible WWFF reference, derive `KFF-XXXX → US-XXXX` via the existing cross-reference
  logic; if that POTA park has a boundary, render it tinted as WWFF; otherwise show a WWFF pin.
- No new server data. Toggle: "WWFF".

### SOTA activation zones (recreate; server-side compute)
Reverse-engineered approach (no third-party API):

- **DEM source**: AWS Terrain Tiles (`elevation-tiles-prod`, Terrarium PNG encoding) — free,
  global, S3-hosted; composites **USGS 3DEP 10 m/3 m in the US** over SRTM/NASADEM. Decode:
  `elev_m = (R*256 + G + B/256) − 32768`.
- **Algorithm** (the "25 m rule"): from the summit pixel, **flood-fill** the connected region of
  pixels with `elevation ≥ summit_elev − 25 m`, then trace that region's outer boundary into a
  polygon. This is exactly "the area within the contour drawn 25 m below the summit, connected to
  the summit."
- **Where**: compute **server-side**, once per summit, cache the polygon in PostGIS
  (`sota_activation_zones`), serve viewport GeoJSON via `/v1/sota/zones?bbox=...`. Keeps DEM tile
  fetching/decoding off-device and shares results across all users.
- **Client**: `ActivitiesClient.fetchSotaZones(...)`, render via the shared polygon path; SOTA
  summit pins remain. Toggle: "SOTA Zones".
- Note resolution/edge cases (knolls, saddle disconnections) — the polygon is an estimate, label
  it as such, matching how the rule is described.

## New experiment flag

Add to `ExperimentalFeature` (`swift/packages/CarrierWaveData/.../ExperimentalFeature.swift`):

- Case: `activityLayers` (proposed) — title "Activity Map Layers", `alpha` maturity.
- Gates the **new** overlays (counties, states, WWFF, SOTA zones, grid squares, TOTA tiles).
  POTA boundaries stay under the existing `.parkGIS`.
- Recommendation: **visible** (not hidden) so users discover it on the reference map, with an
  alpha `ExperimentalBadge` at the menu entry. (Adjustable to opt-in/hidden if preferred.)
- Update the experiments table in `swift/ios/CLAUDE.md` and add the `ExperimentalBadge` at the
  menu entry point, per project rules.

## Toggle UX

Expand the existing `slider.horizontal.3` `Menu` in `ParkSearchMapView` with sections:

- **Programs**: POTA Boundaries · WWFF · SOTA Zones · (Park/Summit Pins, Trails — existing)
- **Administrative**: Counties · States
- **Grids**: Grid Squares · Tiles on the Air

Each toggle backed by `@AppStorage` so choices persist. New overlays default **off** to keep the
map clean on first open.

## Multiplier flagging (#2 — deferred design sketch)

Once overlays land, compute multiplier candidates from the already-loaded polygons:
- POTA∩SOTA / POTA∩WWFF co-location (2-fers) via polygon/point containment.
- County-line straddles (a point/park touching ≥2 county polygons) for QSO-party multipliers.
- Surface as a ranked list beside the map. On-device geometric overlap of visible layers is the
  starting point; revisit server precompute if it proves heavy.

## Sequencing (slices)

1. **Client-only wins** ✅ *(done)* — `activityLayers` experiment; sectioned toggle menu; **Grid
   Squares** and **TOTA tiles** overlays with zoom-gating.
2. **Counties & states** ✅ *(done)* — migration `042_admin_boundaries.sql` (PostGIS) +
   `scripts/import-admin-boundaries.sh` (Census CB import) + `GET /v1/admin/boundaries` (bbox +
   kind) + client `AdminBoundary`/`ActivitiesClient+AdminBoundaries`/`AdminBoundaryCache` +
   `ParkSearchMapKit+Admin` outline overlays + `ParkSearchMapView+AdminBoundaries` (county
   zoom-gate, viewport fetch, eviction). **Data load still pending**: the import script must be run
   against the PostGIS instance to populate the table.
3. **SOTA activation zones** ✅ *(done)* — recreated from AWS Terrarium DEM (no third-party API):
   `src/sota_az.rs` (slippy math + Terrarium decode + flood-fill of the connected region ≥
   `summit − 25 m` + edge-stitch contour + Douglas–Peucker), migration `043`, `POST /v1/sota/zones`
   (returns cached, enqueues bounded background compute), client `SOTAZone` /
   `ActivitiesClient+SOTAZones` / `ParkSearchMapKit+SotaZones` (translucent fills) /
   `ParkSearchMapView+SotaZones` (zoomed-in only, viewport summit gathering, pending-retry).
   Core algorithm covered by Rust unit tests. **Note**: zones compute lazily on first request and
   need outbound access to the Terrarium S3 endpoint from the server.
4. **WWFF** ✅ *(done)* — client-only. Loads US (KFF) references, and for each visible one
   borrows the cross-mapped POTA `US-####` polygon (reusing `/v1/parks/boundaries` +
   `ParkBoundaryCache`), tinted magenta; falls back to a diamond marker where no POTA boundary
   exists. `WWFFRenderItem` + `ParkSearchMapKit+WWFF` + `ParkSearchMapView+WWFF`, zoomed-in only.
5. **Multiplier list (#2)** ✅ *(done)* — on-device geometric overlap scan over the loaded
   overlays: `MultiplierFinder` flags POTA+SOTA (summit-in-park), POTA+WWFF (borrowed polygon),
   and county-line (park/summit within ~1.5 km of a county boundary) candidates; surfaced via a
   `rosette` toolbar button → `MultipliersSheet`, tap-to-recenter. Runs off-main, viewport-bounded.

## Risks / notes

- **Performance**: counties and TOTA tiles are dense — strict viewport + zoom gating and hard
  caps are mandatory (mirror the 400-grid / span guards already in `GridSquareComputation`).
- **Build verification**: this cloud session has no Xcode — Swift changes are validated by the
  SwiftFormat/SwiftLint hooks here; full compilation is verified by Xcode Cloud on merge. Server
  (Rust) and migrations are not wired into CI yet (see root `CLAUDE.md` "Pending Setup").
- **Data licensing/attribution**: Census (public domain), AWS Terrain Tiles / NASADEM / SRTM /
  3DEP (open) — add attributions in `AttributionsView` when those slices land.

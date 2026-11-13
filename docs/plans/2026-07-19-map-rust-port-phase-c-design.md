# Map Rust Port — Phase C Design (Park Search Map)

**Date:** 2026-07-19
**Status:** Approved design (Jay, 2026-07-19). Implementation plan to follow.
**Parent spec:** [2026-07-18-map-views-rust-port-design.md](2026-07-18-map-views-rust-port-design.md)
**Phase B:** [2026-07-19-map-rust-port-phase-b-design.md](2026-07-19-map-rust-port-phase-b-design.md) (merged 49828934)

## Goal

Port the Parks & Summits map to shared Rust — park/summit/WWFF search,
boundary/trail/admin/zone fetch + caching, and the rosette multiplier
geometry — and build the net-new Android park search screen. NEXRAD radar
stays iOS-Swift-only.

## Scope decisions (settled with Jay 2026-07-19)

- **Polygon union: server-side pre-merge.** activities-server unions
  multi-unit park polygons at ingest (Rust `geo` boolean ops);
  `/v1/parks/boundaries` serves ready-merged GeoJSON. Deletes iOS
  `ParkBoundary+Merging.swift` (476 lines, CGPath — unportable to Android);
  no polygon-clipping dependency ships in the mobile binary. Server deploys
  before the app cutover ships.
- **Clustering: native per platform.** Rust serves bbox-scoped pin queries;
  iOS keeps ClusterMap, Android uses osmdroid clustering. Visual grouping
  may differ slightly — accepted; clustering is rendering, not domain logic.
- **Search: SQL in cw-store** (`search_references(query, kinds, limit)`,
  LIKE/FTS on name+ref). Deliberate architecture divergence from the
  faithful-port rule — replaces iOS's load-everything prefix index; parity
  tests assert result sets, not the index mechanism.
- **Admin boundaries port too.** The parent spec's "radar/admin overlays
  remain Swift" is honored in spirit: only NEXRAD radar stays iOS-only. The
  states/counties GeoJSON client ports (it is ~50 lines and the rosette's
  county-line mode needs it on Android).

## Survey findings that drive the design (2026-07-19)

- iOS surface: ~4,800 lines / ~20 files under `Views/Map/`
  (`ParkSearchMapView*`, `ParkSearchMapKit*`, caches, pins). The
  fetch/cache/debounce/evict pattern is duplicated four times (boundaries,
  trails, admin, SOTA zones, WWFF).
- `cw-net::SotaZonesClient` + `ReferenceDataApi::refresh_sota_zones` are the
  established template for GeoJSON fetch clients; `/v1/parks/boundaries`,
  `/v1/trails`, `/v1/admin/boundaries` clients don't exist yet.
- `fetch_pota_parks_in_box` exists in cw-store (used by
  `SessionWizardApi::suggest_park`); no bbox reads for summits/WWFF yet; no
  viewport-scoped SOTA-zone cache read.
- `MultiplierFinder.swift` (177 lines) is pure geometry — the cleanest port.
- `ParkBoundary+Geometry` / `TrailBoundary+Geometry` (buffer skirts,
  point-in-ring, Douglas-Peucker) are portable pure math.
- Android has **no** park surface today (only the External Data download
  card) — the screen is net-new, per the parent spec.
- Grid squares are already ported (`grids_in_region`); TOTA tiles are not.

## Design

### 1. activities-server — merge-on-ingest

Boundary ingest unions each park's multi-unit polygons once (`geo` crate
boolean ops), storing merged geometry; `/v1/parks/boundaries` responses are
therefore pre-merged (still valid GeoJSON FeatureCollections — old clients
unaffected). Simplification tolerance handling unchanged. Release + deploy
via the established local server release recipe **before** the client
cutover tasks ship.

### 2. cw-net — three new GeoJSON clients (SotaZonesClient template)

- `ParkBoundariesClient` — by refs or bbox (+limit+simplify), plus
  single-ref full-res.
- `TrailsClient` — bbox (+limit+simplify).
- `AdminBoundariesClient` — bbox + kind (state|county) (+limit+simplify).

### 3. cw-store — bbox reads, search, GIS cache

- `sota_summits_in_box`, `wwff_in_box` (mirror `fetch_pota_parks_in_box`).
- `search_references(query, kinds, limit)` — SQL name+ref search across
  pota_park / sota_summit / wwff_reference.
- `gis_boundary_cache` table (schema bump): kind
  (park|trail|admin_state|admin_county), key (ref or tile-key), GeoJSON,
  fetched_at; TTL + row-cap eviction replacing the four Swift in-memory
  cache/evict implementations (150 boundaries / 100 trails caps preserved).
- `sota_zones_for_summits(codes)` cached read (closes the viewport-read gap).

### 4. cw-domain — pure geometry

- `park_geometry`: point-in-ring (ray cast), signed area, Douglas-Peucker,
  polygon/trail buffer skirts (100 ft / 30.48 m, averaged vertex normals,
  miter clamp) — ported from `ParkBoundary+Geometry` /
  `TrailBoundary+Geometry` with pinning tests captured before deletion.
- `multiplier`: MultiplierFinder port — POTA+SOTA point-in-polygon,
  county-line point-to-segment proximity (1,500 m, local equirectangular),
  POTA+WWFF pass-through.
- `tota_tiles_in_region` (6-char subsquares) alongside `grids_in_region`.

### 5. cw-ffi — new `ParkMapApi { store, http }`

Not on the store-pure `MapApi` (boundary fetch needs network):

- Viewport pin queries: parks/summits/WWFF in bbox → render-ready records
  (native clustering consumes them).
- `search(query, kinds, limit)`.
- Cache-through fetchers: boundaries (by refs/bbox), trails, admin, SOTA
  zones — read `gis_boundary_cache`, fetch misses, evict per caps.
- WWFF-borrows-POTA resolution — stays client logic but shared in Rust.
- Rosette compute over the viewport's loaded geometry.

### 6. iOS cutover (clean)

`ParkSearchMapView+Data`/`+AdminBoundaries`/`+SotaZones`/`+WWFF` fetch/
cache/evict plumbing collapses onto `ParkMapApi`; deleted:
`ParkBoundary+Merging.swift`, `ParkBoundaryCache.swift`,
`AdminBoundaryCache.swift`, the in-memory name indexes' search path, local
point-in-ring/simplify/buffer implementations. Stays Swift: MKMapView
rendering + overlay diff-sync coordinators, ClusterMap, pin/callout views,
NEXRAD radar, debounce timing.

### 7. Android — net-new park search screen

osmdroid map + native clustering, search field, park/summit/WWFF pins,
boundary/trail/zone/admin overlays via the shared fetch, rosette sheet,
tap-to-callout. Reuses `MapRenderHelpers`. Debounce timing client-side.

## Accepted divergences

- SQL search replaces the in-memory prefix index (result-set parity tested;
  index mechanism intentionally different).
- Native clustering may group pins slightly differently per platform.
- GIS caching moves from per-layer in-memory dictionaries to a shared
  SQLCipher table with TTL — cache hit/miss timing differs from old iOS.

## Out of scope

NEXRAD radar + weather alerts (iOS-only); azimuthal spot map tab (parent
spec exclusion); Phase D items (share renderers, propagation/activation
browser/brag hosts).

## Amendments during implementation (2026-07-19)

- Fetch-limit defaults (parks 50 / trails 50 / admin 500) live in the Rust
  FFI layer; the Android pins cap (500/kind) is client-side and operative.
- Bbox pin queries return a prioritized order (summits by points desc,
  parks/WWFF by reference) so capped subsets are principled; NO zoom-span
  guard on pins (a guard would blank the zoomed-out map — the old iOS code
  full-loaded and clustered at every zoom).
- Search: per-kind limits (10+10) client-side — `search_references` applies
  one shared SQL LIMIT which could starve a kind. The old iOS home-distance
  sort is NOT reproduced (it was parks-only and partial) — SQL relevance
  ranking on both platforms; follow-up if wanted.
- Boundary properties (designation/manager/acreage/etc.) + kind ride the
  GIS cache as GeoJSON Feature envelopes; `FfiGeoBoundary` carries
  `properties_json` + `kind`; admin state/county kind is tagged Rust-side
  (FIPS-length heuristic survives only as the nil-kind fallback).
- Rosette output is merged per-location (kinds[], score = kinds count),
  sorted score-desc/title-asc in Rust; clients render verbatim.
- Android adaptations: rosette trigger is a TopAppBar icon (no chip row on
  that screen); overlay display-list eviction is insertion-order (records
  carry no bbox — iOS evicted by distance from center); boundary tap
  hit-testing lacks iOS's skirt-buffer forgiveness. Both recorded as
  follow-ups.
- Backfill: raw features aren't stored server-side — the deploy aged
  `park_boundaries.fetched_at` on both DBs so the stale-refresh loop
  re-unions everything (batch 20/cycle).

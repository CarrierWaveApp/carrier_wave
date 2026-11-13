# Map Rust Port — Phase C Implementation Plan (Park Search Map)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the Parks & Summits map to shared Rust (search, bbox pin queries, boundary/trail/admin/zone fetch+cache, rosette geometry), pre-merge multi-unit park polygons server-side, and build the net-new Android park search screen.

**Architecture:** activities-server unions park polygons at ingest (`geo` crate); cw-net gains three GeoJSON clients (SotaZonesClient template); cw-store gains bbox reads, SQL search, and a `gis_boundary_cache` table (schema v14); cw-domain gains `park_geometry` + `multiplier` + `tota_tiles_in_region`; a new `ParkMapApi { store, http }` in cw-ffi fronts it all. iOS deletes its merging/cache/search plumbing; Android gets a new screen.

**Tech Stack:** Rust (geo crate server-side only, rusqlite, uniffi), Swift/MapKit + ClusterMap (kept), Kotlin/Compose + osmdroid clustering.

**Spec:** `docs/plans/2026-07-19-map-rust-port-phase-c-design.md`

## Global Constraints

- **Never `cargo fmt`** in `rust/cw-core` OR `server/` (both hand-formatted; gate is build + clippy + test).
- cw-store ids/refs: parks are canonical uppercase refs (`US-0001`); cw-store ids lowercase where uuids.
- iOS compile-check: destination `generic/platform=iOS`; **never** the Simulator. SourceKit "No such module" is stale-index noise.
- Rust gates from `rust/cw-core/` (and separately from `server/`): `cargo build` → `cargo clippy --all-targets` → `cargo test`.
- Android build: `JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home ./gradlew :app:assembleDebug` from `android/`; grep for `BUILD SUCCESSFUL`.
- iOS FFI restage after cw-ffi signature changes: `./scripts/build-xcframework.sh` from `rust/cw-core/`.
- swiftformat → swiftlint before iOS commits; no print/os_log in iOS app code.
- Android: store/network-touching FFI on `Dispatchers.IO`; Android diagnostics go to `AppLog` (util/AppLog.kt), not bare `android.util.Log`.
- Constants (verbatim from Swift, port exactly): boundary in-memory cap **150**, trail cap **100** (preserved as gis cache row caps per kind); trail/boundary buffer skirt **30.48 m (100 ft)** with averaged vertex normals + miter clamp; county-line proximity threshold **1,500 m** in local equirectangular projection; SOTA zone POST chunk **500**; TOTA tiles = 6-char subsquares (~5′ lon × 2.5′ lat) with tile-count cap matching `ParkSearchMapKit+Grids.swift`.
- Parity fixtures captured from Swift **before deletion** (geometry values, rosette results, search result sets).
- Commit after every task.

---

### Task 1: Server — merge-on-ingest for park boundaries

**Files:**
- Modify: `server/src/aggregators/park_boundaries.rs` (1,357 lines — read fully first; it is the ingest pipeline)
- Modify: `server/Cargo.toml` (add `geo` crate for boolean ops; check workspace deps conventions)
- Test: extend the aggregator's test module with multi-unit fixtures

**Interfaces:**
- Produces: ingested park boundary rows whose geometry is the **union** of all of that reference's overlapping unit polygons (single Feature or MultiPolygon per reference where units merge; non-overlapping units remain separate polygons of one MultiPolygon). `/v1/parks/boundaries` output shape is unchanged (still a FeatureCollection) — old clients render it fine.

- [ ] **Step 1:** Read the aggregator: find where per-reference features are grouped/stored on ingest, and the simplification step order (merge BEFORE simplify).
- [ ] **Step 2 (failing tests):** two fixtures — (a) two overlapping rectangles for one ref → union is a single polygon whose area < sum of parts; (b) two disjoint polygons for one ref → MultiPolygon with both, areas preserved. Assert the stored/served geometry.
- [ ] **Step 3:** Implement with `geo::BooleanOps::union` (unary-union the ref's polygons pairwise or via `unary_union` if available in the pinned version). Handle degenerate/self-intersecting inputs by skipping the merge for that ref (log + serve unmerged) rather than failing ingest.
- [ ] **Step 4:** Server gates from `server/`: `cargo build` → `cargo clippy --all-targets` → `cargo test`.
- [ ] **Step 5:** Commit: `server: union multi-unit park polygons at boundary ingest (map port phase C)`

---

### Task 2: Server release + deploy (after Task 1 review passes)

Use the established local server release recipe (docs + the operator's notes: ansible vault file at `~/ansible_pass`, `gh release` fires the tag workflow). Version-bump per `server/` conventions, release, deploy via ansible, verify `/v1/parks/boundaries` for a known multi-unit park (e.g. one that previously required client merging) returns merged geometry. Re-run the boundary ingest/backfill if merged geometry only applies to newly-ingested data — read the aggregator's storage model in Task 1 to determine whether a backfill command/endpoint is needed, and if so include it in Task 1.

- [ ] Release + deploy + curl-verify. Commit any version-bump files: `server: release <version> — merged park boundaries (map port phase C)`

---

### Task 3: cw-domain `park_geometry`

**Files:**
- Create: `rust/cw-core/cw-domain/src/park_geometry.rs`; register in `lib.rs`
- Port sources (read before implementing): `swift/ios/CarrierWave/Views/Map/ParkBoundary+Geometry.swift` (242 — signed area, ray-cast `isPointInRing`, Douglas-Peucker, polygon buffer skirt), `swift/ios/CarrierWave/Views/Map/TrailBoundary+Geometry.swift` (125 — polyline buffer, averaged vertex normals, miter clamp, 30.48 m)

**Interfaces (used by Tasks 6–7 and the rosette):**
- `point_in_ring(point: (f64,f64), ring: &[(f64,f64)]) -> bool`
- `signed_area(ring) -> f64`
- `simplify_dp(points, tolerance_deg) -> Vec<(f64,f64)>`
- `buffer_polygon(ring, meters) -> Vec<(f64,f64)>` and `buffer_polyline(points, meters) -> Vec<(f64,f64)>` (closed skirt)

- [ ] TDD with pinning tests: capture ≥3 concrete input/output vectors per function from the Swift implementations (run mentally/by hand from the Swift math — document each fixture's Swift provenance in a comment). Include point-in-ring edge cases (on-vertex, crossing-count parity) matching Swift's `isPointInRing` semantics exactly.
- [ ] Gates; commit: `rust: park geometry primitives — point-in-ring, DP simplify, buffer skirts (map port phase C)`

---

### Task 4: cw-domain `multiplier` (rosette) + TOTA tiles

**Files:**
- Create: `rust/cw-core/cw-domain/src/multiplier.rs`; register in `lib.rs`
- Modify: `rust/cw-core/cw-domain/src/maidenhead.rs` (add `tota_tiles_in_region` next to `grids_in_region`)
- Port sources: `swift/ios/CarrierWave/Views/Map/MultiplierFinder.swift` (177 — read fully; `containingPark` :95-110, `minDistanceToRingMeters`/`pointToSegmentMeters` :112-176), `ParkSearchMapKit+Grids.swift` (TOTA tile rect math)

**Interfaces (used by Task 7):**
- `pub struct MultiplierCandidate { pub kind: MultiplierKind, pub latitude: f64, pub longitude: f64, pub refs: Vec<String>, pub distance_m: Option<f64> }` with `enum MultiplierKind { PotaSota, PotaWwff, CountyLine }`
- `find_multipliers(summits, park_polygons, wwff_borrowed, county_rings) -> Vec<MultiplierCandidate>` — signatures take plain slices of (ref, rings) tuples; exact shapes chosen by the implementer to mirror the Swift inputs.
- `tota_tiles_in_region(center, lat_span, lon_span, cap) -> Vec<TotaTile { tile: String, south, west, north, east }>`

- [ ] TDD: POTA+SOTA (summit inside/outside a two-ring polygon), county-line (point 1,499 m vs 1,501 m from a segment — pin the 1,500 m threshold), TOTA tile rects for a known grid (assert 6-char subsquare corner math), tile cap.
- [ ] Gates; commit: `rust: rosette multiplier geometry + TOTA tiles (map port phase C)`

---

### Task 5: cw-net — ParkBoundaries/Trails/AdminBoundaries clients

**Files:**
- Modify: `rust/cw-core/cw-net/src/reference_data.rs` (or sibling module if cleaner — match how `SotaZonesClient` lives; read it first at `reference_data.rs:254+`)
- Port sources: `swift/ios/CarrierWave/Services/ActivitiesClient+ParkBoundaries.swift` (83), `+Trails.swift` (45), `+AdminBoundaries.swift` (43) — exact endpoints/params

**Interfaces (used by Task 7):**
- `ParkBoundariesClient::by_refs(refs, simplify) / by_bbox(bbox, limit, simplify) / full_res(ref)` → GeoJSON strings + parsed per-ref grouping like the Swift `BoundariesResponse.toParkBoundaries()` (WITHOUT the merging half — server pre-merges now; keep the resilient skip-bad-feature decode from `ParkBoundary.swift`'s `SafeFeature`).
- `TrailsClient::by_bbox(bbox, limit, simplify)`
- `AdminBoundariesClient::by_bbox(bbox, kind, limit, simplify)` with `kind ∈ {state, county}`

- [ ] TDD with canned GeoJSON fixtures (happy path, one malformed feature skipped, empty response). Follow SotaZonesClient's test style.
- [ ] Gates; commit: `rust: park boundary/trail/admin GeoJSON clients (map port phase C)`

---

### Task 6: cw-store — bbox reads, SQL search, gis cache (schema v14), zone reads

**Files:**
- Modify: `rust/cw-core/cw-store/src/sota_summit.rs`, `wwff_reference.rs` (bbox reads mirroring `pota_park.rs:144` `fetch_pota_parks_in_box`)
- Create: `rust/cw-core/cw-store/src/reference_search.rs` (`search_references`)
- Create: `rust/cw-core/cw-store/src/gis_cache.rs`
- Modify: `migrations.rs` (SCHEMA_VERSION 13 → 14; include a v13→v14 upgrade-path test like the callbook one), `lib.rs`
- Modify: `sota_zone` store module — add `sota_zones_for_summits(codes) -> Vec<(code, geometry_geojson)>` cached read

**Interfaces (used by Task 7):**
- `search_references(query: &str, kinds: &[RefKind], limit: i64) -> Vec<RefSearchHit { kind, reference, name, latitude, longitude }>` — case-insensitive match on name OR reference, parks/summits/WWFF, ranked: exact-ref match first, then prefix, then substring; deterministic tiebreak by reference.
- `gis_boundary_cache` table: `kind TEXT, cache_key TEXT, geojson TEXT, fetched_at INTEGER, PRIMARY KEY(kind, cache_key)`; `upsert_gis`, `fetch_gis(kind, keys, now, ttl)`, `evict_gis(kind, cap)` deleting oldest-fetched beyond cap (caps: park 150, trail 100, admin 150, zone unlimited-but-TTL'd; TTL 7 days — boundaries change rarely; constant per kind in one place).

- [ ] TDD: bbox inclusion/exclusion, search ranking (exact ref beats prefix beats substring; kind filter; limit), cache upsert/fetch TTL/evict-oldest, migration upgrade-path test.
- [ ] Gates; commit: `rust: bbox reads, reference search, gis_boundary_cache v14, zone reads (map port phase C)`

---

### Task 7: cw-ffi — `ParkMapApi`

**Files:**
- Create: `rust/cw-core/cw-ffi/src/park_map_api/` (`mod.rs`, `records.rs`) — submodule layout like `map_api/`
- Modify: `rust/cw-core/cw-ffi/src/lib.rs` (register)

**Interfaces (records all `uniffi::Record`; verify against consumers in Tasks 9–13):**
- `FfiParkPin { reference, name, latitude, longitude, kind (park|summit|wwff), activation_count: Option<i64>, altitude_m: Option<i64> }`
- `FfiRefSearchHit` mirroring `RefSearchHit`
- `FfiGeoBoundary { reference, name: Option<String>, geojson: String }`
- `FfiMultiplierCandidate` mirroring cw-domain
- `FfiTotaTile { tile, south, west, north, east }`
- `ParkMapApi::new(store, /* http via the same construction the other net-backed APIs use — read ReferenceDataApi::new */)`
- Methods: `pins_in_box(bbox, kinds, limit)`; `search(query, kinds, limit)`; async `park_boundaries(refs, simplify)` / `park_boundaries_in_box(bbox, limit, simplify)` / `park_boundary_full(ref)` / `trails_in_box(...)` / `admin_boundaries_in_box(..., kind)` — all cache-through `gis_boundary_cache` (read → fetch misses → upsert → evict); `sota_zones_for(codes)` (cache read; misses via the existing refresh path semantics — read how `refresh_sota_zones` stores rows and reuse); `wwff_borrowed_boundaries(wwff_refs)` — the WWFF-borrows-POTA matching ported from `ParkSearchMapView+WWFF.swift` (chunked, cache-first); free exports `totaTilesInRegion(...)` and `pointInRing(point: FfiCoordinate, ring: Vec<FfiCoordinate>) -> bool` (iOS boundary tap hit-testing consumes it in Task 10); `find_multipliers(...)` taking the viewport's loaded geometry refs and resolving rings from cache.
- Error model: network failures on cache-warm paths return cached data + no error; cold-cache network failure throws `CwError` (client shows the layer empty, matching iOS behavior).

- [ ] TDD: store-backed tests for pins_in_box/search passthrough, cache-through logic with a canned-fetch stub (hit → no fetch; miss → fetch+upsert+evict), rosette end-to-end from cached geometry. Network clients themselves were tested in Task 5 — stub them here following however qrz_api tests fake HTTP (check; if no pattern exists, factor the cache-through into a pure function over a `fetch_fn` closure and test that).
- [ ] Full Rust gates; commit: `rust: ParkMapApi — pins, search, cache-through GIS fetch, rosette (map port phase C)`

---

### Task 8: Regenerate FFI artifacts

- [ ] `./scripts/build-xcframework.sh` from `rust/cw-core/`; Android `assembleDebug` (BUILD SUCCESSFUL + grep `ParkMapApi` in generated cw_ffi.kt); commit `CwFfi+Generated.swift`: `ffi: regen bindings with ParkMapApi (map port phase C)`

---

### Task 9: iOS — search + pins onto ParkMapApi

**Files:**
- Modify: `ParkSearchMapView.swift`, `ParkSearchMapView+Data.swift`, `ParkSearchCluster.swift` (feed ClusterMap from `pins_in_box` records instead of full snapshots), the search-field path (`NameIndexSearch` call sites in this surface)

- [ ] Swap search to `parkMapApi.search(...)`; swap pin loading to bbox queries on region change (keep the existing debounce); keep ClusterMap + pin views untouched. Delete this surface's use of `parksSnapshot()`-style full-dataset loads and the name-index search path (leave the caches themselves — other surfaces may use them; grep first and report what remains).
- [ ] Format/lint/compile-check; commit: `ios: park search + pins onto ParkMapApi (map port phase C)`

---

### Task 10: iOS — overlays + rosette cutover, deletions

**Files:**
- Modify: `ParkSearchMapView+Data.swift` (boundary/trail fetch), `+AdminBoundaries.swift`, `+SotaZones.swift`, `+WWFF.swift`, `+Multipliers.swift`
- Delete: `ParkBoundary+Merging.swift`, `ParkBoundaryCache.swift`, `AdminBoundaryCache.swift`; the local `pointInPolygon`/simplify-tolerance geometry in `+Data.swift` (point-in-ring → FFI or the boundary hit-test moves onto cw-domain via a small FFI export if needed — check what Task 7 exposed)
- Modify: `MultiplierFinder.swift` → delete, call `find_multipliers` FFI; `TrailBoundary`/`ParkBoundary` geometry extensions reduce to decode+render only

- [ ] Each overlay's fetch/cache/evict plumbing → the corresponding ParkMapApi method (keep MKMapView diff-sync renderers). Rosette sheet consumes `FfiMultiplierCandidate`. Grep for dangling symbols after deletions; FILE_INDEX updates.
- [ ] Format/lint/compile-check; commit: `ios: park overlays + rosette onto ParkMapApi; delete client merging + GIS caches (map port phase C)`

---

### Task 11: Android — park search screen foundation

**Files:**
- Create: `android/.../ui/parks/ParkSearchScreen.kt`, `ParkSearchViewModel.kt`
- Modify: navigation host + tab/More entry (follow the app's overlay navigation pattern), `CwApp.kt` (construct `ParkMapApi`)

- [ ] osmdroid map + osmdroid clustering (RadiusMarkerClusterer or the repo's precedent if one exists) over `pins_in_box` (debounced region listener, Dispatchers.IO); search field over `search(...)` with result list → tap centers map; pin tap → callout card (reuse the callout card pattern from MapScreen). Errors → AppLog.
- [ ] Build green; commit: `android: park search screen — pins, clustering, search (map port phase C)`

---

### Task 12: Android — overlays

- [ ] Boundary/trail polygons (GeoJSON parse → osmdroid Polygons/Polylines; buffer skirts via cw-domain exports where iOS draws them), SOTA zones, admin boundaries (state/county toggle), WWFF (borrowed polygons + diamond fallback), TOTA tiles + grid squares layer toggles — all through ParkMapApi cache-through fetchers, reusing `MapRenderHelpers` (extend it for GeoJSON→osmdroid conversion ONCE, shared by all layers).
- [ ] Build green; commit: `android: park map overlays — boundaries, trails, zones, admin, WWFF, tiles (map port phase C)`

---

### Task 13: Android — rosette sheet

- [ ] `find_multipliers` over the current viewport's loaded refs → bottom sheet listing candidates (kind icon, refs, distance for county-line) with tap-to-center. Mirror `MultipliersSheet.swift` copy.
- [ ] Build green; commit: `android: rosette multiplier finder sheet (map port phase C)`

---

### Task 14: Docs, changelog, gates

- [ ] CHANGELOG (root + Android sections), spec amendments for any implementation deviations, FILE_INDEX updates, handoff/memory notes. Full gates: server cargo suite, cw-core suite, iOS compile-check, Android assembleDebug.
- [ ] Commit: `docs: map Rust port phase C changelog + spec amendments`

---

### Task 15: Final whole-branch review

- [ ] Whole-branch review (most capable model) with the ledger's Minor-findings roll-up; fix Critical/Important; then merge per the established finishing flow. Device pass owed on both platforms post-merge.

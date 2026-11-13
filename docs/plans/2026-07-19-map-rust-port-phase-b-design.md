# Map Rust Port — Phase B Design (Embedded Map Cards)

**Date:** 2026-07-19
**Status:** Approved design (Jay, 2026-07-19). Implementation plan to follow.
**Parent spec:** [2026-07-18-map-views-rust-port-design.md](2026-07-18-map-views-rust-port-design.md)
**Phase A handoff:** [2026-07-19-map-rust-port-phase-a-handoff.md](2026-07-19-map-rust-port-phase-a-handoff.md)

## Goal

Move the seven embedded map card surfaces onto shared Rust and bring Android to
full parity — including building the Android host surfaces that don't exist yet.
iOS cutover is clean (Phase A style): duplicate Swift math and hand-rolled
network clients are deleted, not kept as fallbacks.

## Scope decisions (settled with Jay 2026-07-19)

- **Club map lookup: grid-first, lookup fills gaps.** Clients plot member
  `lastGrid` centroids immediately (fast first paint), then a Rust
  QRZ → HamDB batch lookup refines pins and fills members with no grid on
  file. Precise callbook lat/lon wins over grid centroids when available.
- **Android: full parity now.** Build the missing host surfaces (timeline
  replay screen, spots mini-map, QSO detail card, session detail card,
  callsign map section) this phase, not just cards on existing hosts.
- **API shape: card methods + CallbookApi.** `MapApi` grows store-backed
  per-card methods returning render-ready data (like Phase A's `qso_map`).
  Callsign-location lookup lives on the existing `QrzApi` (batch `locate` +
  cw-store cache). Simple cards compose from the existing free FFI exports —
  no store round-trip for data already in memory. Timeline decay/SNR curves
  are pure Rust functions so replay renders identically on both platforms.
  Playback/animation state stays client-side (marshaling frames across FFI is
  the wrong boundary).

## Survey findings that drive the design (2026-07-19)

- iOS has **three** independent grid→coordinate implementations
  (`MaidenheadConverter.swift`, `SpotsMiniMapView.gridToCoordinates`, Rust
  FFI), plus duplicate distance (`HaversineDistance`,
  `MaidenheadConverter.distanceMiles`) and SNR-color/decay logic
  (`TimelineMapView`, `SpotsMiniMapView`).
- `ClubMapView+Lookup.swift` (298 lines) hand-rolls QRZ XML session auth +
  HamDB fallback + `MemberLocationCache` (30-day JSON cache) — duplicating
  `QrzApi.lookup_callbook`'s exact QRZ→HamDB merge, which already exists in
  Rust but **drops lat/lon** (both Rust clients parse only `grid`; QRZ and
  HamDB both return coordinates, and Swift's clients use them).
- `TimelineMapDataActor` (261 lines) is the heaviest surface: own SwiftData
  context, RBN spot fetch, spotter-grid lookups via Swift `HamDBClient`
  (batches of 30, skimmer-suffix stripping), QSO+spot event merge.
- All needed source data already exists in cw-store: `session_spot`
  (spotter, spotter_grid, snr, source), `pota_park` (latitude/longitude),
  `rove_stop` (my_grid), plus QSOs and sessions.
- Android's `ClubMapView.kt` currently plots grid centroids only (no lookup);
  it upgrades to the shared grid-first + refine flow.
- `QSOMapView` (Phase A) is the reference consumption pattern.

## Design

### 1. cw-domain — `timeline.rs` (new)

Pure functions ported from `TimelineMapView`/`TimelineMapDataActor` before
deletion:

- Merged QSO + RBN-spot event stream ordering.
- Spot opacity decay: 300 s full → 600 s gone, with the existing easing.
- SNR → marker radius banding (0–40 dB → 10–36 pt).
- SNR → color band index (client maps index → platform color).

Pinning tests assert values captured from the Swift implementation.

### 2. cw-net — lat/lon in callbook clients

- `QrzClient`: parse `<lat>`/`<lon>` XML tags into `QrzLookup`.
- `HamdbClient`: deserialize `lat`/`lon` JSON fields into `HamdbLookup`.

Additive struct fields; existing consumers unaffected.

### 3. cw-store — `callbook_location` cache (schema bump)

New table: `callsign TEXT PRIMARY KEY, latitude REAL, longitude REAL,
grid TEXT, source TEXT ('qrz'|'hamdb'), fetched_at INTEGER`. 30-day TTL
enforced on read (replaces iOS `MemberLocationCache` semantics). Plus
timeline source queries: session QSOs + RBN-filtered `session_spot` rows by
session id.

### 4. cw-ffi

- `MapApi.session_map(session_id) -> FfiSessionMapData` — QSO pins + rove-stop
  pins, arcs, bounds. Store-authoritative session map path.
- `MapApi.session_timeline(session_id) -> FfiTimelineData` — merged event
  stream with resolved coordinates. `MapApi` stays store-pure: spotter
  coordinates resolve from `spotter_grid` or the `callbook_location` cache
  (skimmer suffixes stripped in Rust); still-unresolved spotter callsigns are
  returned in an `unresolved_spotters` list, which the client passes to
  `QrzApi.locate` and then re-calls `session_timeline` (now cache-warm). This
  replaces the Swift `HamDBClient` batching in `TimelineMapDataActor`.
- `MapApi.qso_detail_map(qso_id) -> FfiQsoDetailMap` — my/their coordinates
  with grid-first → `pota_park` lat/lon fallback, arc, distance, bearing.
- `QrzApi.locate(callsigns: Vec<String>) -> Vec<FfiCallsignLocation>` —
  batch, read-through cache, QRZ → HamDB fallback, 3-wide concurrency +
  politeness delay inside Rust. Result carries coordinate + `source`
  (`qrz`/`hamdb`/`grid`) so clients can refine grid-centroid pins in place.
- Free exports: timeline decay/radius/color-band curves. The callsign map
  section needs nothing new (`maidenheadCoordinate` / `maidenheadDistanceKm` /
  `maidenheadBearing` already shipped in Phase A).

### 5. iOS cutover (clean)

Deleted outright: `TimelineMapDataActor` (261), `ClubMapView+Lookup` (298),
`MemberLocationCache.swift` (107), `SpotsMiniMapView.gridToCoordinates`,
`HaversineDistance` use in `QSODetailView+Map`, `ClubMapView`'s private
`isWideSpan` / `regionForAnnotations` (→ `mapBoundsFor`). All map-surface
`MaidenheadConverter` call sites swap to the FFI grid functions.

**Amended during implementation (2026-07-19):** `HamDBClient.swift` was
planned for deletion but has six live consumer files outside the map
surfaces (RBNPanelView, PropagationCheckEnrichment,
AzimuthalStandaloneView+Fetch, UserProfileService, P2PService,
CallsignLookupService) — it stays until those surfaces port in Phases C/D.
No map surface references it anymore.

Stays Swift: MapKit rendering, callouts/chrome, `nudgeCamera`, cluster
tinting, band/RST color mapping.

### 6. Android — full parity

- Club map: grid-first pins, then `locate()` refinement.
- New surfaces: QSO detail map card (Logbook), session detail map card,
  callsign map section, spots mini-map (spots tab), timeline replay screen
  (Compose scrubber over `session_timeline` + shared decay curves).

### 7. Testing & gates

- Parity fixtures captured from Swift **before deletion**: timeline merge
  order, decay/radius values, distance labels.
- Cache TTL tests; QRZ/HamDB lat/lon parse tests; locate batch fallback tests.
- Gates: cargo build/clippy/test (no fmt); swiftformat → swiftlint → iOS
  compile-check (`generic/platform=iOS`); Android assembleDebug; xcframework
  regen via `scripts/build-xcframework.sh` after FFI signature changes.

## Accepted divergences

- QSO-detail distance moves from Swift haversine-miles to the shared R=6371
  haversine — same ~0.3% drift class already accepted in Phase A.
- Club map pins may shift slightly when `locate()` refinement lands after
  first paint (grid centroid → precise coordinate). Intentional consequence
  of grid-first.
- **Added during implementation (2026-07-19):**
  - Timeline replay excludes WEATHER/SOLAR/NOTE pseudo-modes via the shared
    `VISIBLE_QSO` rule; the old Swift actor leaked them (latent bug, fixed
    by the port per the mandatory metadata-modes rule).
  - Timeline session-spot fetch caps at 1000 newest (store
    `MAX_FETCH_LIMIT`) vs Swift's 2000 oldest — only reachable in extreme
    RBN-volume sessions.
  - Both platforms' spots mini-maps converge on the shared 10–36 pt SNR
    size curve; old iOS mini-map used a local 8–20 pt formula (markers
    slightly larger now).
  - Club-map first-frame framing uses the shared camera math (min span 5°)
    vs the old iOS 0.5° floor — tight clubs start slightly more zoomed out.
  - Android QSO-detail footer shows km + mi + bearing (iOS shows the
    user-preference unit, no bearing) and renders single-pin maps when only
    one endpoint resolves — deliberate Android superset.
  - Timeline replay spot circles are SNR-band-colored on both platforms; old
    iOS used flat green.

## Out of scope (later phases)

Park search map + boundary fetch (Phase C); share renderers + propagation
check / activation browser / brag share hosts (Phase D); azimuthal spot map
tab (excluded in parent spec).

# Map Rust Port — Phase A Handoff

**Date:** 2026-07-19
**Status:** Phase A merged to `main` (merge head `121a8739`). Phases B–D not started.
**Spec:** [2026-07-18-map-views-rust-port-design.md](2026-07-18-map-views-rust-port-design.md)
**Plan (executed):** [2026-07-18-map-rust-port-phase-a-plan.md](2026-07-18-map-rust-port-phase-a-plan.md)

## What shipped

One-call shared map view-model in Rust; both platforms render it; the iOS
SwiftData map pipeline is gone.

| Layer | What | Where |
|---|---|---|
| cw-domain | Great-circle paths with antimeridian splitting (reuses the single azimuthal slerp) | `rust/cw-core/cw-domain/src/great_circle.rs` |
| cw-domain | Dateline-aware bounds + camera spans (padding 1.3/1.5, globe threshold 90°) | `rust/cw-core/cw-domain/src/map_bounds.rs` |
| cw-store | Map source rows + filter options SQL | `rust/cw-core/cw-store/src/map_data.rs` |
| cw-ffi | `MapApi.qso_map(FfiMapFilter) -> FfiQsoMapData` — clusters/pins with callout metadata, arcs, bounds, stats, filter-sheet options, cap handling | `rust/cw-core/cw-ffi/src/map_api/` (`records.rs`, `filter.rs`, `aggregate.rs`, `mod.rs`) |
| cw-ffi | Free exports **built for Phase B — do not rename**: `great_circle_arc`, `map_bounds_for`, `compute_map_statistics(FfiMapStatInput)`, `maidenhead_grid_bounds` (4-char), `maidenhead_tile_bounds` (6-char) | `map_api/mod.rs` |
| iOS | `QSOMapView` consumes `MapApi`; **deleted**: `MapDataLoadingActor`, `QSOMapView+Loading`, `GridOverlayDataActor` (no SwiftData fallback — map is FieldStore-authoritative); `GridSummaryLoader` now feeds grid tracker; `ActivationMapHelpers`/`ActivationStatsHelper` delegate geodesics/bounds/stats to FFI; `QSOArc` is a stored-path struct | `swift/ios/CarrierWave/Views/Map/`, `Views/POTAActivations/ActivationMapHelpers.swift` |
| Android | Map tab parity: filter sheet, callout card, per-segment arc polylines, worked/confirmed grid overlay, stats strip; `mapApi` on `CwApp` | `android/.../ui/map/` (`MapViewModel.kt`, `MapScreen.kt`, `MapFilterSheet.kt`, `QsoCalloutCard.kt`) |

Commit sequence (task-per-commit, no squash): `5bd565c0` → `121a8739` on the
merged branch; changelog in `a7c2dffd`.

## The gotcha that almost shipped broken

`maidenhead_tile_bounds` requires **≥6-char** grids and returns `None` for
4-char tiles. The grid-tile SQL emits **4-char** keys. Android's grid overlay
silently rendered nothing until `121a8739` added `maidenhead_grid_bounds`
(4-char, 2°×1°) and swapped the call site. If you touch grid overlays in
Phase B+, mind which precision you're holding; there's a pinning test in
`map_api/mod.rs` (`maidenhead_grid_bounds_accepts_4char`).

## Accepted divergences (reviewed, intentional — do not "fix" casually)

- **Date filters** run through the shared logbook query DSL: **day
  granularity, local-timezone** resolution (old Swift compared exact UTC
  timestamps). Both platforms use day-granularity date pickers, so UX is
  unchanged. Changing this would fork map filtering from logbook-query
  filtering.
- **Distances** use the single haversine (R=6371) implementation; old iOS
  used CLLocation's WGS84 geodesic (~0.3% drift in avg/max distance and
  watts-per-mile).
- **`park:` filter** is case-insensitive in the DSL vs Swift's exact match
  (POTA refs are canonically uppercase — no practical difference).
- **Metadata enrichment index** (weather/solar/WPM/equipment) fetches a
  single 1000-row page; misses degrade to plain pins, never dropped QSOs.

## Owed / follow-ups

1. **Device verification (the big one).** ~~iOS half~~ **verified on device
   2026-07-19** — Map tab against Jay's real logbook looks correct after the
   clean cutover. Still owed: Android device/emulator pass (filters, arcs,
   grid overlay toggle, callouts, and the new camera auto-fit); recipe is in
   the android-build-env memory / `android/` docs.
2. ~~Hoist `VISIBLE_QSO` SQL const to `pub(crate)` in analytics.rs and delete
   the byte-identical copy in `map_data.rs`.~~ **Done 2026-07-19.**
3. ~~Android `MapViewModel.updateFilter` launches overlapping `reload()`s —
   add `Job` cancellation so a stale slow response can't land after a newer
   one.~~ **Done 2026-07-19.**
4. ~~Android ignores `FfiQsoMapData.bounds` — wire camera auto-fit for parity
   with iOS first-load framing.~~ **Done 2026-07-19** (one-shot
   `zoomToBoundingBox`; near-global spans fall back to world zoom).
5. iOS `ActivationMapView` makes one `greatCircleArc` FFI call per QSO in a
   loop (same O(n) as the old Swift math; marshaling overhead unmeasured).
   Perf-glance only if huge activations feel slow.

## Starting Phase B (embedded map cards)

Phase B = session logger map, session detail card, timeline replay, QSO/
callsign detail arcs, spots mini-map, club map (member coordinate lookup
moves to Rust: QRZ → HamDB fallback + cache in cw-net). Per the spec it gets
its own brainstorm → spec → plan cycle. Head start already in place:

- The free FFI exports above cover arc/bounds/stats needs for most cards.
- `SessionQSOMap`/`MapContentBuilders` already construct `QSOArc` via
  `greatCircleArc` (rewired in Task 7).
- Club map: iOS `ClubMapView+Lookup.swift` (QRZ→HamDB, cached) is the port
  source; `QrzApi` exists in cw-ffi, HamDB does not yet.

## Build/regen recipes (verified this session)

- Rust gates from `rust/cw-core/`: `cargo build` → `cargo clippy
  --all-targets` → `cargo test`. **Never `cargo fmt`** (hand-formatted).
- After any cw-ffi signature change: `./scripts/build-xcframework.sh` from
  `rust/cw-core/` (~2 min; commit the regenerated tracked
  `CwFfi+Generated.swift`; the `.xcframework` itself is gitignored).
- Android: `JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
  ./gradlew :app:assembleDebug` from `android/` — regenerates the
  **gitignored** `uniffi/cw_ffi/cw_ffi.kt` itself; grep the log for
  `BUILD SUCCESSFUL` (exit codes lie).
- iOS: compile-check only, destination `generic/platform=iOS`; SourceKit
  "No such module" diagnostics are stale-index noise when xcodebuild says
  BUILD SUCCEEDED.

## Phase B status (2026-07-19)

Implemented on `feat/map-rust-port-phase-b` (spec + plan + 20+ commits,
task-per-commit with per-task review). See
[2026-07-19-map-rust-port-phase-b-design.md](2026-07-19-map-rust-port-phase-b-design.md)
for the amended deletion list and accepted divergences. Device verification
owed on both platforms after merge.

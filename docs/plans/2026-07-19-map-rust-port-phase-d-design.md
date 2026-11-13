# Map Rust Port — Phase D Design (Share Renderers + Remaining Android Hosts)

**Date:** 2026-07-19
**Status:** Approved design (Jay, 2026-07-19). Final phase of the map port.
**Parent spec:** [2026-07-18-map-views-rust-port-design.md](2026-07-18-map-views-rust-port-design.md)
**Phase C:** [2026-07-19-map-rust-port-phase-c-design.md](2026-07-19-map-rust-port-phase-c-design.md) (merged c09088ee)

## Goal

Rust rasterizes the themed flat/azimuthal share maps to PNG (pixel-identical
across platforms); Android gains the three remaining hosts — brag share card,
**full** POTA activation browser, and propagation check. A Rust ADIF writer
lands as a hard dependency of Android bulk export (paying the long-standing
"no Rust ADIF writer" debt).

## Scope decisions (settled with Jay 2026-07-19)

- **Activation browser: FULL experience** on Android — list, detail + map
  card, QSO timeline, awards, conditions, bulk ADIF export. The largest
  single host of the whole port (~8,900 iOS lines across 28 files).
- **Propagation check: build now** despite Alpha/hidden status on iOS —
  session core ports to Rust (`PropagationApi`) so both platforms share the
  polling/enrichment engine; Android host built this phase.
- **Ring labels: no text in Rust rasters.** The one in-raster text case
  (azimuthal "5k mi" ring captions) returns as `{x, y, text}` anchors; each
  platform overlays natively. No Rust font dependency.
- **Parity = golden Rust PNGs.** Both platforms call the same Rust code, so
  cross-platform pixel-identity is inherent; comparison against the old
  CoreGraphics output is a visual spot-check, not byte parity.
- **iOS ADIF swap is scoped** to the POTA bulk-export surface this phase;
  the app-wide Swift ADIF writer call sites (uploads, other exports) are a
  follow-up once the Rust writer has soaked.

## Survey findings that drive the design (2026-07-19)

- Rasterizers to replace: `FlatMapRenderer(+Drawing)` 674 lines +
  `AzimuthalMapRenderer` 392 = ~1,066 lines of CoreGraphics. Five flat
  `ColorTheme`s (midnight/warm/ocean/arctic/ember) + a separate hardcoded
  azimuthal palette (to be unified).
- `ShareMapStyle.usesCustomRenderer` splits the world: `.azimuthal` + 5 flat
  themes → Rust; `.adaptive`/`.flat`/`.globe` (MKMapSnapshotter) stay Swift.
- Orchestrators (`BragSheetShareRenderer`, `ActivationShareRenderer`) and
  all card chrome (SwiftUI `ImageRenderer`) stay native — only the map
  sub-image becomes a Rust PNG.
- `cw-domain::azimuthal` (full projection, tested) and
  `cw-domain::coastline` (Natural Earth 110m, 103 rings) already exist;
  no raster crate anywhere in the workspace (tiny-skia is net-new);
  `Vec<u8>` FFI returns have precedent (CIV frames, escrow blobs).
- Coastline antimeridian: iOS draws each continent 3× at ±360° shifts and
  lets CG clip — the Rust port uses **explicit splitting** instead.
- `TOTABragSheetRenderer` is MapKit-snapshot-based → stays Swift, untouched.
- `AzimuthalStandaloneView` is the excluded live spot-map tab → untouched.
- Propagation check: ~3,500 iOS lines; enrichment falls back to
  `HamDBClient` — replaced by the Phase B `QrzApi.locate`/callbook-cache
  path (kills HamDB consumer #2 of 6; the other four are out-of-phase
  general services).
- Android has zero share/export code today; brag sheet is display-only.
- cw-net already has a PSK Reporter client; RBN spot access exists via the
  spot engine/proxy paths.

## Design

### 1. cw-domain — `share_render` (tiny-skia)

- `ShareTheme`: one struct unifying the 5 flat palettes + azimuthal palette
  (ocean, land fill/stroke/hatch, grid line, accent, background).
- Flat renderer: equirectangular viewport (Phase A `map_bounds` math,
  antimeridian-aware), ocean fill, lat/lon grid, coastlines (explicitly
  split at ±180°), geodesic trace lines (`great_circle`), RST-colored pins,
  count pins, center marker — port of `FlatMapRenderer(+Drawing)`.
- Azimuthal renderer: range rings, coastlines, traces, pins, center marker
  on `azimuthal.rs` — port of `AzimuthalMapRenderer` minus `drawRingLabel`.
- Output: RGBA → PNG bytes + `Vec<RingLabel { x, y, text }>` (azimuthal
  only). Golden-PNG pinning tests per theme.

### 2. cw-domain — ADIF writer

Faithful port of the Swift ADIF export (field set, ordering, escaping,
header). Golden-file parity tests against fixtures captured from the Swift
writer. Lives beside the existing ADIF reader.

### 3. cw-ffi

- `render_share_map(style: FfiShareMapStyle, input: FfiShareMapInput)
  -> FfiShareMapImage { png_bytes, ring_labels }` — style enum covers the
  six custom variants only; input carries pins/traces/center/bounds built
  by the caller from existing snapshot data (brag QSO snapshots, activation
  QSOs — same sources the Swift orchestrators use today).
- `AdifApi`: `export_qsos(...) -> String` (+ options mirroring the iOS
  bulk-export sheet).
- `PropagationApi`: session core — start/poll/stop a check session (RBN +
  PSK Reporter via cw-net), windowed spot accumulation, enrichment via the
  callbook cache/`locate` flow, results summary. Clients render; Rust owns
  session state and polling cadence.

### 4. iOS cutover

- Delete `FlatMapRenderer.swift`, `FlatMapRenderer+Drawing.swift`,
  `AzimuthalMapRenderer.swift` (~1,066 lines). `BragSheetShareRenderer` /
  `ActivationShareRenderer` / `PropagationCheckMapCard` /`ThemedMapImage`
  call `render_share_map` for custom styles and composite the PNG; ring
  labels overlaid in SwiftUI.
- `PropagationCheckEnrichment` moves onto `QrzApi.locate` + callbook cache
  (HamDB fallback deleted from this surface); the session/polling layer
  swaps onto `PropagationApi`.
- POTA bulk ADIF export sheet swaps to `AdifApi` (scoped swap; app-wide
  writer call sites are follow-up).

### 5. Android — three new hosts

- **Brag share card**: stats card + Rust PNG map + ring-label overlay +
  share intent (Android's first share feature). Style picker mirroring the
  iOS six custom styles (+ no MapKit variants on Android).
- **POTA activation browser (full)**: activation list, detail (map card via
  Phase A/B FFI, QSO timeline), awards views, conditions, bulk ADIF export
  via `AdifApi` + share intent.
- **Propagation check**: start sheet, live view (map + azimuthal cards over
  `PropagationApi` state), results view.

### 6. Testing & gates

Golden PNG tests (per style/theme) in cw-domain; ADIF golden-parity vs
Swift fixtures; PropagationApi session-state tests with canned spot feeds;
the standard four-toolchain gates; xcframework regen after FFI changes.

## Accepted divergences

- Rust-rendered custom-style maps replace CoreGraphics output — visually
  equivalent by spot-check, not byte-identical to the old renders.
- Ring labels are platform-overlaid text (font metrics differ slightly from
  the old in-raster `UIFont.systemFont(ofSize: 7)`).
- Android share cards have no MapKit-styled variants (adaptive/flat/globe
  remain iOS-only, as MapKit is).

### Execution amendments (accepted during implementation)

- **`TOTABragSheetRenderer` was cut over, not out of scope.** The spec listed
  it under "Out of scope" as a MapKit path, but it actually consumed the
  deleted CoreGraphics renderers, so Task 7 routed its custom styles through
  the Rust rasterizer too. Correct the Out-of-scope note below accordingly.
- **Bulk ADIF: only Combined mode moved to Rust.** `AdifApi.exportActivation`
  / `exportBulk` back the single-activation sheet and the bulk sheet's
  Combined mode; Split-by-Park and the session/multi-op exports
  (`FullADIFExportActor`, `ADIFExportService+Session`) stay on the Swift
  writer, as planned.
- **v15 index is an expression index** `ON qso(UPPER(park))`, not a plain
  column index — the activation rollup and detail fetch both compare
  `UPPER(park)`, which a bare `qso(park)` index cannot serve (verified via
  `EXPLAIN QUERY PLAN`).
- **Legacy iOS propagation artifacts re-enrich at view time.** Since
  enrichment moved to Rust and old saved `PropagationCheck` blobs may carry
  nil skimmer grids, `PropagationCheckResultsView` re-enriches those (only
  blob spots with `skimmerGrid == nil`) via `QrzApi.locate` when opened.
- **Android propagation check is passive/receive-only.** No transmit /
  Auto-CQ mode (no Android radio bridge), no saved history or Compare view
  (no `PropagationCheck` store on Android yet), and `solar = null` into the
  config (no Android NOAA/HamQSL client) — all the contract-valid "host
  skipped the fetch" case. Follow-ups if those platforms gain the deps.
- **Android propagation per-band breakdown sorts alphabetically**, not by
  iOS `standardBandOrder` (pre-existing Android convention; a display-order
  follow-up, not a data difference).

## Out of scope

`AzimuthalStandaloneView` (excluded tab); app-wide iOS ADIF writer swap
beyond the bulk-export sheet (Split-by-Park and session/multi-op exports stay
on the Swift writer); the four remaining HamDBClient consumers (RBN panel,
profile, P2P, general callsign lookup — later work; HamDBClient itself
survives this phase for them, now down to those four after
`PropagationCheckEnrichment` was deleted). (`TOTABragSheetRenderer` was
originally listed here but turned out to use the deleted CoreGraphics
renderers and was cut over — see Execution amendments above.)

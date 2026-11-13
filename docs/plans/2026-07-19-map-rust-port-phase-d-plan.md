# Map Rust Port — Phase D Implementation Plan (Share Renderers + Remaining Hosts)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rust PNG share renderers (flat + azimuthal, 6 custom styles), a Rust ADIF writer, a shared PropagationApi, iOS cutover (~1,066 CoreGraphics lines deleted), and three net-new Android hosts (brag share card, full POTA activation browser, propagation check).

**Architecture:** `cw-domain::share_render` (tiny-skia; themes unified; ring labels as data) + `cw-domain` ADIF writer; cw-ffi gains `render_share_map`, `AdifApi`, `PropagationApi`; iOS orchestrators composite Rust PNGs; Android builds the last three hosts.

**Tech Stack:** Rust (tiny-skia — NET-NEW dep, png encode via tiny-skia's own encoder or `png` crate), Swift/SwiftUI ImageRenderer compositing, Kotlin/Compose + share intents.

**Spec:** `docs/plans/2026-07-19-map-rust-port-phase-d-design.md`

## Global Constraints

- **Never `cargo fmt`** in rust/cw-core; clippy `-D warnings`; hand-formatted.
- iOS compile-check `generic/platform=iOS`, never Simulator; SourceKit no-such-module = stale noise.
- Android: gradle from `android/`, grep `BUILD SUCCESSFUL`; FFI on `Dispatchers.IO`; errors → `AppLog`.
- xcframework regen after FFI signature changes, before iOS tasks.
- swiftformat → swiftlint before iOS commits; RadioService.addLog, never print/os_log.
- **Renderer constants (port verbatim from Swift before deletion):** the 5 `FlatMapRenderer.ColorTheme` palettes (FlatMapRenderer.swift:24-87) and the azimuthal palette (AzimuthalMapRenderer.swift:89-95) — capture exact RGBA values into the Rust `ShareTheme` with a pinning test each; coastline crosshatch spacing/angle, grid-line spacing, pin radii, trace widths — all captured from the Swift drawing code with fixture provenance comments.
- Coastline antimeridian: explicit split at ±180° (NOT triple-draw-and-clip).
- Ring labels: returned as anchors `{x, y, text}`, never rasterized in Rust.
- ADIF writer: byte-golden parity with the Swift writer's output for identical inputs (capture fixtures BEFORE any Swift changes).
- Commit after every task; task-per-commit, no squash.

---

### Task 1: cw-domain `share_render` — themes + flat renderer

**Files:** Create `rust/cw-core/cw-domain/src/share_render/mod.rs`, `themes.rs`, `flat.rs`; Cargo.toml adds `tiny-skia` (+ `png` if tiny-skia's encoder is insufficient — prefer tiny-skia-only); lib.rs + FILE_INDEX registration.
**Port sources (read fully):** swift/ios/CarrierWave/Views/BragSheet/FlatMapRenderer.swift (351) + FlatMapRenderer+Drawing.swift (323).
**Interfaces (used by Tasks 2, 4):**
- `ShareTheme { ocean, land_fill, land_stroke, land_hatch, grid_line, accent, background: Rgba }` + `fn theme(style) -> ShareTheme` for midnight/warm/ocean/arctic/ember (+azimuthal palette added in Task 2).
- `FlatMapSpec { width, height, center, lat_span, lon_span, pins: Vec<SharePin { lat, lon, color: PinColor, count: Option<u32> }>, traces: Vec<(from, to)>, center_marker: Option<(f64,f64)> }`
- `render_flat(spec, theme) -> Vec<u8>` (PNG bytes).
- Steps: TDD with golden-PNG pinning tests (deterministic output — hash or byte-compare a committed fixture per theme; small canvases keep fixtures tiny). Antimeridian coastline split explicit; viewport math reuses `map_bounds`/Phase A conventions.
- Commit: `rust: share_render flat rasterizer + unified themes (map port phase D)`

### Task 2: cw-domain `share_render` — azimuthal renderer + ring labels

**Files:** Create `share_render/azimuthal.rs`; extend themes.
**Port source:** swift/ios/CarrierWave/Views/BragSheet/AzimuthalMapRenderer.swift (392) — range rings, coastline via `azimuthal.rs` projection, traces (`great_circle_path`), pins, center marker; `drawRingLabel` (247-279) is NOT rasterized — emit `RingLabel { x: f32, y: f32, text: String }` anchors with the same positions/strings ("5k mi" formatting ported exactly).
**Interfaces:** `AzimuthalMapSpec { width, height, center_grid/center coords, max_distance_km, pins, traces }`, `render_azimuthal(spec, theme) -> (Vec<u8>, Vec<RingLabel>)`.
- Golden-PNG + ring-label-anchor pinning tests.
- Commit: `rust: share_render azimuthal rasterizer + ring label anchors (map port phase D)`

### Task 3: cw-domain ADIF writer

**Files:** Create `rust/cw-core/cw-domain/src/adif_writer.rs` (beside the existing ADIF reader — locate it first and match its module conventions).
**Port source:** the Swift ADIF export used by the POTA bulk-export sheet — grep swift/ios for the writer feeding `ADIFExportSheet.swift` (440 lines, Views/POTAActivations/) and port its field set/ordering/escaping/header verbatim.
- Fixtures: run the Swift writer mentally/by-hand over ≥3 representative QSO sets (normal, unicode/special chars in fields, minimal-field QSO) — capture expected ADIF strings as committed fixtures with provenance comments; byte-golden tests.
- Commit: `rust: ADIF writer with Swift golden parity (map port phase D)`

### Task 4: cw-ffi — `render_share_map` + `AdifApi`

**Files:** Create `rust/cw-core/cw-ffi/src/share_render_api.rs` (or map_api submodule — match conventions), `adif_api.rs`; records; lib.rs registration.
**Interfaces (Tasks 7, 9, 10, 11 consume):**
- `FfiShareMapStyle` enum: Azimuthal, Midnight, Warm, Ocean, Arctic, Ember.
- `FfiShareMapInput { width, height, center_lat/lon (or grid), lat_span/lon_span (flat) / max_distance_km (azimuthal), pins: Vec<FfiSharePin>, traces: Vec<FfiShareTrace>, show_center_marker }`
- `render_share_map(style, input) -> FfiShareMapImage { png_bytes: Vec<u8>, ring_labels: Vec<FfiRingLabel> }` (free export or on MapApi — free is fine, it's store-less).
- `AdifApi` (store-backed): `export_activation(session_id/park filters, options...) -> String` mirroring the iOS bulk-export sheet's options — read ADIFExportSheet.swift for the exact option set (date ranges, park filter, etc.) and bind them.
- Store-backed tests for AdifApi; passthrough tests for render.
- Commit: `rust: render_share_map + AdifApi (map port phase D)`

### Task 5: cw-ffi — `PropagationApi`

**Port sources (read fully):** swift/ios/CarrierWave/Services/PropagationCheckSession.swift (311) + PropagationCheckSession+Polling.swift, Models/PropagationCheck*.swift (553), Views/PropagationCheck/PropagationCheckEnrichment.swift (137).
**Interfaces (Tasks 8, 12 consume):** `PropagationApi { store, http, secure? }` — `start_session(config) -> session handle/state`, `poll() -> FfiPropagationState` (windowed enriched spots: RBN + PSK Reporter via cw-net clients; spotter/receiver grid enrichment via callbook cache + the locate flow — NOT HamDB), `stop()`, `results() -> FfiPropagationResults`. Cadence/windowing constants ported verbatim from the Swift session.
- Canned-feed tests (fake fetch closures like ParkMapApi's cache-through pattern) for windowing/enrichment/results math.
- Commit: `rust: PropagationApi shared session engine (map port phase D)`

### Task 6: FFI regen

- xcframework + Android bindings; verify new symbols; commit Generated.swift. `ffi: regen bindings with share render + adif + propagation (map port phase D)`

### Task 7: iOS — share renderer cutover

**Files:** Delete FlatMapRenderer.swift, FlatMapRenderer+Drawing.swift, AzimuthalMapRenderer.swift. Modify BragSheetShareRenderer(.swift/+Drawing), ActivationShareRenderer.swift, PropagationCheckMapCard.swift, ThemedMapImage.swift; FILE_INDEX.
- Custom styles → `renderShareMap` (build FfiShareMapInput from the same snapshot/cluster data the orchestrators already assemble; UIImage(data: pngBytes); ring labels overlaid in the SwiftUI composite). MapKit styles untouched. Grep dangling symbols.
- Gates + commit: `ios: share maps onto Rust rasterizer; delete CoreGraphics renderers (map port phase D)`

### Task 8: iOS — propagation check onto PropagationApi + scoped ADIF swap

- PropagationCheckSession/-Polling swap onto PropagationApi (view models consume FfiPropagationState); PropagationCheckEnrichment deleted (enrichment is in Rust; HamDB consumer #2 gone). ADIFExportSheet's writer call → AdifApi (scoped swap; grep confirms other Swift ADIF call sites untouched).
- Gates + commit: `ios: propagation check onto PropagationApi; bulk ADIF export onto AdifApi (map port phase D)`

### Task 9: Android — brag share card

- ui/brag: share button on BragSheetScreen → style picker (6 custom styles) → compose stats card + Rust PNG map (+ ring labels overlay for azimuthal) → Bitmap → share intent (FileProvider). Mirror iOS BragSheetShareCardView layout per docs/design-language.
- Commit: `android: brag sheet share card on Rust rasterizer (map port phase D)`

### Task 10: Android — activation browser part 1 (list, detail, timeline)

- New ui/activations: activation list (sessions with parks — same data source iOS POTAActivationsView uses via existing Session/ActivityLog FFI; verify what APIs exist from Phase B and the sessions-hunterlog port), detail screen (header stats, SessionMapCard reuse from Phase B, QSO timeline list mirroring QSOTimelineView), navigation from Sessions/More per app pattern.
- Commit: `android: POTA activation browser — list, detail, timeline (map port phase D)`

### Task 11: Android — activation browser part 2 (awards, conditions, bulk export, share)

- Awards views (existing pota_awards store/FFI surface — check cw-ffi for the awards API the iOS POTAAwardsView uses post-port), conditions display, bulk ADIF export via AdifApi → share intent, activation share card via render_share_map.
- Commit: `android: activation browser — awards, conditions, ADIF export, share (map port phase D)`

### Task 12: Android — propagation check

- New ui/propagation: start sheet (config), live view (map card + azimuthal card over FfiPropagationState — azimuthal card renders via render_share_map re-render per poll OR native Canvas from projected points; choose the cheaper faithful option and report), results view. Entry: Experiments-equivalent or More tab per app convention.
- Commit: `android: propagation check host on PropagationApi (map port phase D)`

### Task 13: Docs, changelog, gates

- CHANGELOG (root + Android), spec amendments, FILE_INDEX, memory-worthy notes; four-toolchain gates.
- Commit: `docs: map Rust port phase D changelog + spec amendments`

### Task 14: Final whole-branch review + merge

- Opus whole-branch review with ledger triage; fix Critical/Important; merge --no-ff; device pass owed post-merge.

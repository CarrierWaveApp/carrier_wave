# Spots Engine → Rust (SpotEngineApi)

**Goal:** one shared Rust spots engine, modeled on Sweep's (the more powerful of the two),
superset-extended with iOS's needs-matching. Ship order: build engine → swap **iOS** onto it
(gaining Sweep's sources + SQL query filtering + a query editor UI) → swap **Sweep** onto it →
delete both Swift engines. Parity is the acceptance bar ([[rust-swift-parity]]).

Status: PLANNED. Nothing implemented.

---

## 1. Engine comparison (as of 2026-07-02)

| Capability | Sweep (macOS) | iOS | Rust engine (target) |
|---|---|---|---|
| Sources | RBN, POTA, SOTA, WWFF, DXSummit, DXHeat, DXWatch, **telnet DX cluster** (8) | RBN, POTA, SOTA, WWFF, PSKReporter (5), fetch scattered per-view | All 9 (union), config-gated per platform |
| Architecture | Single `SpotAggregator` (@MainActor, 30 s poll, `async let` fan-out) | No aggregator — `SpotMonitoringService` + `SpotsService` + `SOTASpotsCache` + `OnAirCard` each fetch | One engine, tokio poll loop, listener callbacks |
| Unified model | `UnifiedSpot` (28 fields) → `EnrichedSpot` | Same `UnifiedSpot` (shared via CarrierWaveCore) but enrichment differs | `FfiUnifiedSpot`/`FfiEnrichedSpot` superset |
| Dedup | Source-priority map (`rbn`=0 … `cluster`=7), `dedupKey = call-band` | Per-view: `callsign|band` preferring POTA>WWFF>SOTA>RBN | Sweep's priority table, per-source-configurable |
| Enrichment | Grid/state (HamDB, enrichment dataset), distance/bearing, `SpotRegion`, DXCC lookup + needed status, SKCC, operator name, batched QRZ/HamDB callsign lookup | HamDB grids (cap 15/cycle) + states (cap 10/cycle), distance/bearing/region, SKCC | All of Sweep's, with iOS's per-cycle lookup caps |
| Needs matching | DXCC-only (`DXCCNeededChecker`) | **Richer**: DXCC, WAS, POTA-hunter, WWFF-hunter, custom patterns (`NeedsEngine`/`SpotNeedsMatcher`) | iOS's full `NeedsSnapshot` matching |
| Widget filters | mode/source/band/region/continent/status/age/text | source/band/mode/continent/hideWorked/clubOnly/needsOnly/age | Union, as one `FfiSpotFilters` |
| SQL query engine | GRDB `scope.spots`/`spot_observations`/`spotters` + `qsos`/`dxcc`/`dxcc_status`/`polo_notes` mirror; Query Workbench (editor, run/profile/format, saved queries, starter queries); `BandScopeQueryRunner` (1 s, `allowedSpotIDs` drives band scope) | Hidden experiments only: `QueryRunnerView` (runs imported `.cwquery`), `BandScopeQueryRunner` (POTA-only ingest) | Engine-owned in-memory SQLite, same schema; validation/profile/interrupt in FFI |
| Spot observations | Per-skimmer fan-out rows + spotter location index (2-tier: CTY centroid, HamDB) | None | Ported |
| Persistence | SwiftData `SessionSpot` (session capture); disk caches (enrichment dataset, polo notes, parks) | SwiftData `SessionSpot` + cw-store via `EntityWriteSink` | Stays host-side (see Non-goals) |
| Remote | BLE `RemoteSpot` + `SubscribeFilter` | — | Stays host-side (Sweep converts from FFI snapshot) |

**What iOS gains from the swap:** 3 DX-web sources + cluster telnet, real aggregation/dedup,
DXCC-needed status on spots, spot observations, the SQL filter path, and the query editor.
**What must not regress on iOS:** needs matching (WAS/POTA/WWFF/custom), SessionSpot recording,
TuneIn/SDR handoff, per-callsign activator mode, fetch limits/caps, spot age prefs.
**What must not regress on Sweep:** band scope SQL allow-list latency (1 s), observation rows for
the workbench, BLE remote, vim-mode filtering (stays a view-side predicate).

---

## 2. Architecture

Follow the SDR-port precedent (domain → net → ffi; host keeps UI + platform I/O):

```
rust/cw-core/
├── cw-domain/src/spots/          # pure logic, no I/O
│   ├── model.rs                  # UnifiedSpot, EnrichedSpot, SpotSource, dedup key
│   ├── merge.rs                  # priority dedup, prune, source-priority table
│   ├── region.rs                 # SpotRegion / SpotRegionGroup / SpotContinent (grid→region)
│   ├── filters.rs                # widget filter predicates (union of both platforms)
│   ├── needs.rs                  # NeedsSnapshot + SpotNeedsMatcher port
│   ├── cluster_parser.rs         # DXSpotParser port (DX de …, parseMode, parseCWSpeed, split-info)
│   └── observations.rs           # SpotObservationRow / SpotterRow projection
├── cw-net/src/
│   ├── dxsummit.rs dxheat.rs dxwatch.rs   # new HTTP clients (existing rbn/pota/sota/wwff reused)
│   ├── hamdb.rs                  # HamDB grid/state lookups
│   ├── enrichment_dataset.rs     # activities-server callsign-enrichment dataset (ETag cache)
│   └── cluster.rs                # telnet DX cluster (tokio TcpStream, line buffer, login, SH/WWV cycle)
└── cw-ffi/src/spot_engine_api.rs # SpotEngineApi (async_runtime = tokio) + scope SQLite
```

**SpotEngineApi** owns:
- a poll loop (default 30 s, configurable) fanning out to enabled sources concurrently;
  telnet cluster is a persistent stream feeding the same merge path
- merge → prune (max age) → enrich → publish via `SpotEngineListener` callback
  (`on_spots_updated(generation: u64)`) — hosts re-read a snapshot, they don't get pushed arrays
- `snapshot(filters: FfiSpotFilters?) -> FfiSpotSnapshot` (filtered, sorted, with
  `allowed_by_query` applied when a band-scope query is active)
- an **in-memory rusqlite DB** with the `scope.*` schema + mirrored `qsos`/`dxcc`/`dxcc_status`/
  `polo_notes` tables and the `cw_user_grid_distance_km` function. Plain rusqlite (spots are
  ephemeral; no SQLCipher — do NOT attach the encrypted cw-store DB)
- query surface: `run_query`, `profile_query` (EXPLAIN QUERY PLAN), `validate_scope_query`
  (must emit `spot_id`), `set_band_scope_query(sql?)`, `interrupt_query`, error line/col from
  `sqlite3_error_offset`, `format_sql` (Rust port of Sweep's `SQLFormatter`, fixture parity
  vs the Swift formatter's output)
- enrichment caches in Rust: grid/state (1 h TTL, 200 LRU), enrichment-dataset index,
  per-cycle HamDB caps (15 grid / 10 state — iOS's budget, adopted engine-wide)

**Host-fed inputs (FFI setters, keeps the engine platform-agnostic):**
- `set_needs_snapshot(FfiNeedsSnapshot)` — host computes it (iOS `NeedsEngine` today; Sweep
  feeds DXCC-needed only). Rust-side needs computation from cw-store is a **follow-up**, not
  this campaign (Sweep is still cw-store `.off`).
- `set_qso_mirror(rows)` / incremental upsert — feeds the workbench `qsos` table
  (Sweep already mirrors; iOS mirrors the same projection from cw-store)
- `set_user_context(grid, callsign, worked_today_keys)` — distance/bearing origin, self-spot,
  dupe partitioning
- park/summit coordinate resolution stays host-side (POTAParksCache / SOTASummitsCache),
  same as the SDR port precedent

**Config (`FfiSpotEngineConfig`):** enabled sources, poll interval, max spot age, per-source
fetch limits (iOS `SpotFetchLimits` values), cluster node host/port/login, activities base URL,
QRZ credentials via `SecureStore` (reuse `cw.qrz.*` namespace from QrzApi).

**Lifecycle:** `start(listener)` / `stop()`; `pause()`/`resume()` for iOS backgrounding.
All store-touching FFI calls off-main on hosts ([[uniffi-async-dispatcher]] ANR risk).

---

## 3. Phases

### Phase 1 — cw-domain `spots/` (pure, headless-verifiable)
Port from Swift with fixture parity tests (capture real JSON/HTML/telnet fixtures from each
source; Swift-vs-Rust output diff, same approach as QueryParityTests):
- `UnifiedSpot` mapping from all 9 source payloads (reuse existing rbn/pota/sota/wwff decoders;
  add DXSummit dual-date decode, DXHeat, DXWatch compact-array + `ci` block, cluster lines, PSKR)
- merge/dedup/prune (`SpotAggregator.mergeSpots` semantics, priority table verbatim)
- `SpotRegion`/group/continent from grid — port the 14-region classifier exactly
- filter predicates: union of Sweep's `BandMapView`/`SpotListView` stack and iOS `SpotFilters.apply`
- `SpotNeedsMatcher` + `NeedsSnapshot` model (DXCC/WAS/POTA/WWFF/custom patterns)
- cluster `DXSpotParser` + `SplitInfoParser` + mode/WPM heuristics
- observation/spotter row projection
**Gate:** cargo build + clippy + tests green; fixture parity vs Swift outputs.

### Phase 2 — cw-net clients
- `dxsummit.rs`, `dxheat.rs`, `dxwatch.rs` (incremental `lastId`), `hamdb.rs`,
  `enrichment_dataset.rs` (ETag conditional GET, 12 h staleness)
- `cluster.rs`: tokio TcpStream, line framing, login prompt handling, 5-min SH/WWV + SH/FILTER
  cycle, reconnect with backoff
**Gate:** wiremock-style tests against fixtures; manual smoke against live endpoints.

### Phase 3 — cw-ffi `SpotEngineApi` + scope SQLite
- engine loop, listener, snapshot, filters, needs/qso-mirror/user-context setters
- in-memory scope DB + schema + `cw_user_grid_distance_km` + starter-query compatibility
  (all 10 Sweep starter queries must run unmodified)
- query validate/run/profile/interrupt with line/col errors; band-scope allow-list evaluation
  (re-run active query ≤ 1 s after each merge, expose `allowed_spot_ids` in snapshot)
- regen bindings via `scripts/build-xcframework.sh`; additive-only `CwFfi+Generated.swift`
**Gate:** cw-ffi tests incl. an end-to-end fake-source engine test; workspace gate green.

### Phase 4 — iOS swap (device-gated)
Replace internals, keep contracts:
- `SpotMonitoringService` becomes a thin adapter: owns a `SpotEngineApi`, translates
  `FfiSpotSnapshot` → existing `[EnrichedSpot]` callback so `LoggingSessionManager+Spotting`
  `recordSpots` / SessionSpot persistence / `EntityWriteSink` path is untouched
- hunter mode = engine global feed + filters; activator mode = engine filtered to own callsign;
  `SpotsService` per-callsign fetch → engine query; delete `SOTASpotsCache`, `POTAClient+Spots`
  fetch paths, `SpotMonitoringService+HunterFetch`, `+Enrichment` (engine does it)
- `OnAirCard`, `POTASpotsView`, `RBNPanelView` re-point at engine snapshots
- needs: iOS keeps `NeedsEngine` (computes snapshot) → `set_needs_snapshot`; delete
  `SpotNeedsMatcher` Swift impl (engine returns `matched_needs` per spot)
- TuneIn handoff: build `FfiTuneInSpot` from engine spots (unchanged host coordinate resolution)
- new sources on iOS: DX-web trio + cluster ship **default-off** behind source toggles in the
  spot filter sheet (DECIDED 2026-07-02); cluster gets a node host/port/login config UI seeded
  with Sweep's defaults
- background: `pause()` on scene-phase background, `resume()` + immediate poll on foreground
**Gate:** parity fixtures still green; device verify: hunter list, activator session with
SessionSpot recording (two-device sync spot check), On Air card, TuneIn, memory/hang check with
500-spot RBN load (realistic-volume rule).

### Phase 5 — iOS query editor (ships with or right after Phase 4)
Promote the hidden experiments into a real surface:
- new `SpotQueryEditorView`: SwiftUI `TextEditor`/UITextView wrapper (monospace), run/profile/
  **format** buttons (format via the `format_sql` FFI), error banner with line/col from FFI,
  row-limit + show-more — a port of Sweep's `QueryWorkbenchModel`
- saved queries: reuse the `.cwquery` format + `SavedQueryStore` (already importable from Sweep);
  seed Sweep's `StarterQueries`
- schema help: static reference sheet (port `SchemaBrowserView` copy)
- band-scope/SQL filter mode in the hunter spot list: `SpotFilterSheet` gains
  "Filter by saved query" (mirrors Sweep's `bandScopeFilterMode`), driven by
  `set_band_scope_query` + snapshot `allowed_spot_ids`
- un-hide `QueryRunnerView`/`BandScopeQueryRunner` experiments or fold them into the new view
**Gate:** all starter queries run on-device against live spots; slow-query warning parity.

### Phase 6 — Sweep swap
- `SpotAggregator` becomes an adapter over `SpotEngineApi` (same `[EnrichedSpot]` published
  property, `spotsVersion` bump on listener callback) — every consumer view keeps compiling
- delete: 7 HTTP clients, `TelnetClusterClient`+`ClusterManager` internals (keep the terminal
  UI reading engine's raw cluster line tap — add `on_cluster_line` to listener), GRDB
  `scope.*` schema + `BandScopeQueryRunner`, Swift `SQLFormatter` (Format button re-points at
  `format_sql` FFI). Query Workbench re-points at engine's query FFI; the workbench
  window/editor UI stays
- keep: SwiftData SessionSpot persistence, BLE `SpotAggregator+Remote` (converts from engine
  snapshot), vim-mode filter, all views
- QSO mirror for workbench joins: Sweep feeds `set_qso_mirror` from its existing GRDB qso
  mirror source (Sweep stays cw-store `.off`; engine must not require cw-store)
- Sweep builds from main repo, not worktrees ([[cw-sweep-worktree-builds]]); xcodegen after
  file changes ([[cw-sweep-xcodegen]])
**Gate:** workbench starter queries + saved queries byte-identical results vs GRDB path on a
captured spot corpus; band scope visual parity; BLE remote round-trip.

### Phase 7 — delete + docs
Remove dead Swift (Sweep `Services/Spots` clients, iOS fetch services), update FILE_INDEXes,
CHANGELOG, memory notes. Follow-ups filed: Rust-side needs computation from cw-store;
Android spots UI on the same engine; TOTA spot source.

---

## 4. Non-goals / stays host-side
- SessionSpot persistence + cloud sync (existing seams; separate migration campaign)
- BLE remote wire format (Sweep)
- Park/summit coordinate caches (host-resolved, SDR-port precedent)
- NeedsSnapshot computation (host `NeedsEngine` for now)
- TOTA spots (separate client, not in either engine's feed today)
- Query Workbench macOS window chrome (UI stays Swift; formatting logic moves to Rust `format_sql`)

## 5. Risks
- **Telnet cluster on iOS**: long-lived TCP in a mobile lifecycle; mitigated by pause/resume +
  default-off. Verify no socket leak across background cycles.
- **Enrichment volume**: 500-spot RBN loads + HamDB caps — engine must batch exactly like iOS
  or we re-create the hard-lock-with-production-data failure mode.
- **Two SQLite worlds during transition**: Sweep runs GRDB and engine DB side-by-side until
  Phase 6 cutover; don't dual-write longer than one release.
- **FFI callback → MainActor**: republish snapshots on main; never let SwiftUI observe across
  the FFI boundary directly ([[waterfall-rendering]] observation-overhead lesson).
- **Panics**: every fallible engine path must return `Result` — a panic in a non-throwing
  export is a crash ([[ffi-panic-crash]]).
- **Lowercase ids** anywhere the engine touches cw-store-adjacent ids ([[cwstore-lowercase-ids]]).

## 6. Key files (current Swift sources of truth)
- Sweep: `swift/macos/CWSweep/Services/Spots/SpotAggregator*.swift`, `Services/Cluster/*`,
  `Models/Spots/*`, `Services/Query/BandScopeQueryRunner.swift`, `Views/Query/*`
- iOS: `Services/SpotMonitoringService*.swift`, `Services/SpotsService.swift`,
  `Services/{NeedsEngine,SpotNeedsMatcher,CTYService}.swift`,
  `Views/ActivityLog/{ActivityLogSpotsList*,SpotFilterSheet}.swift`, `Views/Logger/POTASpotsView*.swift`
- Rust: `cw-net/src/{rbn,pota,sota,wwff}.rs`, `cw-ffi/src/{spots_api,pskreporter}.rs` (SpotsApi
  is superseded by SpotEngineApi — deprecate after Phase 6), `cw-domain/src/query/` (logbook
  query language — unrelated to the spots SQL path, do not conflate)

---

## 7. Status log

- **2026-07-03 — Phase 5 implemented** (branch `feat/spots-phase5-query-editor`).
  `SpotQueryEditorView` + `SpotQueryEditorModel` (port of Sweep's `QueryWorkbenchModel` over
  `run_query`/`profile_query`/`format_sql` FFI) replace the hidden `QueryRunnerView`; saved
  queries reuse the shared `.cwquery` `SavedQueryStore` (iCloud `Documents/Queries`, factory
  extracted to `SavedQueryStores`) seeded with Sweep's `StarterQueries` (ported verbatim);
  schema help ported from Sweep's `SchemaBrowserView`/`SchemaCatalog` copy
  (`SpotSchemaHelpView`/`SpotSchemaCatalog`). `SpotFilterSheet` gained "Filter by saved query"
  (`SpotFilters.savedQueryID` → `SpotEngineProvider.applyBandScopeQuery` →
  `set_band_scope_query`; hunter list gates on snapshot `allowed_spot_ids`, errors fall back to
  widget filters). `BandScopeQueryRunner` re-pointed at the engine (POTA-only GRDB ingest
  deleted); engine `qsos` table fed via new `SpotQueryQsoMirror` (newest 5K, 1K batches,
  off-main). Deferred: on-device starter-query verification + slow-query-warning parity
  (user-gated gate); Rust-side dxcc/polo_notes seeding beyond CTY.

# Rust analytics surface — design (Phase 4 item #6: aggregation reads)

**Date:** 2026-06-20
**Status:** READ SOURCES COMPLETE — N0–N6 plus the MyParks per-park rollup and N5
state/entity follow-ons are all implemented end-to-end (cw-store SQL + cw-ffi + Swift
`AnalyticsReadSource` + cross-impl parity), green in the package loop (19 cw-store cargo
tests, 12 Swift parity tests across two classes; clippy + swiftlint clean). The brag
sheet is a deliberate **first cut** — only the SQL-trivial period metrics; distance /
streak / windowing / new-this-period / activation-grouping stay SwiftData-side. The one
remaining piece is **app-target routing**: pointing the consuming actors
(StatsComputationActor, POTAAwardsActor, GridOverlayDataActor, AsyncServicePresenceCounts,
EquipmentStatsActor, MyParksView, BragSheetComputationActor) at `AnalyticsReadSource`
gated by `CwStoreQSOMode` — device-gated, like the write seam — so the read sources are
dormant until then. See the decomposition section for per-slice status.
**Companions:**
[Phase 4 cutover status](2026-06-20-phase4-cutover-status.md) ·
[rust-core migration](2026-06-13-rust-core-migration.md) ·
[QSO read cutover slice B (query compiler) design](2026-06-15-qso-cutover-B-query-compiler-design.md) ·
[QSO write-cutover handoff](2026-06-17-qso-write-cutover-handoff.md)

---

## TL;DR

The per-row **list** reads cut over to cw-store (slices A/B/C). The remaining read
debt is **aggregation**: every dashboard stat, award rollup, map summary, and
brag-sheet metric still scans SwiftData on a background actor. cw-store today can
*filter* (the `.cwquery` DSL → `compile_where`) and *project/count rows*, but has
**no `GROUP BY` / aggregate surface**. This doc designs that surface: a small catalog
of typed, SQL-`GROUP BY`-backed aggregation FFI functions that reuse the existing DSL
`WHERE` compiler and the canonical grouping keys already in `cw-domain`
(band / mode-family / DXCC / grid / service-type), fronted on the Swift side by an
`AnalyticsReadSource` protocol with SwiftData + Rust impls so each surface can run in
`shadow` and be **parity-diffed in the package test loop** (no device needed).

**Why this is the tractable Phase 4 read item:** unlike the write seam (gated on the
unreliable device test runner), analytics read sources live in `CarrierWaveData` and
verify with `cargo test` + `swift test` here. It is also the largest remaining read
piece and partly cross-language (Rust SQL + DTOs first).

---

## Current state

### Demand side — iOS aggregations still on SwiftData

All run on background actors, mostly batched (500 QSO/batch) into `Sendable`
snapshots, then single-pass accumulate. Inventory (file : symbol → what it computes):

| Surface | Symbol | Computes | Group keys |
|---------|--------|----------|-----------|
| Dashboard core | `Views/Dashboard/StatsComputationActor.swift` | total QSOs, unique bands/grids/entities/parks, confirmed QSLs, successful/attempted activations, activity-by-date, streaks, WAS-by-mode, top freq/friend/hunter, DXCC-new-this-year | band, grid, dxcc, park, date, mode |
| (helper) | `Views/Dashboard/QSOStatistics.swift` | in-memory cache over a pre-fetched `[QSO]` | — |
| Smart Spots needs | `Services/NeedsEngine.swift` | DXCC/WAS/POTA/WWFF "not yet worked" sets (grid-aware) | dxcc, state, park, mode-family |
| POTA awards | `Models/POTAAwardsActor.swift` (+`+WAS250`) | activation groups `(park, UTC-date)`, **unique QSOs per activation deduped by (callsign,band,mode)**, successful ≥10, WAS-250-by-mode | park+date, state, mode |
| Upload counts | `Views/Dashboard/AsyncServicePresenceCounts.swift` | uploaded/pending unique-QSO counts per service | service_type (dedupe by qso_id) |
| Brag sheet | `Services/BragSheet/BragSheetComputationActor.swift` | per-period totals/rate/distance/streaks/POTA/CW/records | date-window, band, mode, grid |
| Equipment | `Views/Dashboard/EquipmentStatsActor.swift`, `Views/Settings/EquipmentItemDetailActor.swift` | top rigs/antennas/keys by session, QSO-magnet, combos; per-item band/mode/distance breakdown | **LoggingSession** + QSO |
| Map | `Views/Map/MapDataLoadingActor.swift`, `GridOverlayDataActor.swift`, `Sessions/TimelineMapDataActor.swift` | filter option lists, annotations/arcs, unique states/entities, per-grid counts/status | band/mode/park/state filters, grid tile |
| My Parks | `Views/Map/MyParksView.swift` `computeMyParkEntries` | per-park activation/hunt counts + last-worked | park |
| Day summary | `Services/DaySummaryDataActor.swift` | QSOs+sessions for a UTC day | date-window |
| Diagnostics | `Views/Dashboard/StatsReportBuilder.swift` | category filter-trace for bug reports | (filter trace) |

Performance note: nearly all obey the batching rule (`BoundedDescriptor`, 500/batch,
fresh `ModelContext`). **`MyParksView.computeMyParkEntries` is an unbounded full-table
load** (flagged in PERFORMANCE.md terms) — the analytics surface fixes it for free.

### Supply side — cw-store read/query infra (what exists)

- **`cw-domain`** owns the canonical grouping keys + labels, all in Rust:
  `band.rs` (`BAND_ORDER`, `derive_band`), `mode.rs` (`ModeFamily`, `family()`),
  `location_prefix.rs` (`PrefixCountry`/`COUNTRIES` DXCC table w/ lat-lon),
  `maidenhead.rs` (grid↔coord, tile bounds), `service_type.rs`.
- **`cw-store`** SQLCipher DB, schema v3. `qso` table indexed on
  `callsign / band / mode / qso_date / dirty`. DSL compiler
  `cw-store/src/query/compiler.rs::compile_where(&ParsedQuery) -> (String, Vec<SqlValue>)`
  lowers the `.cwquery` AST (`cw-domain/src/query/ast.rs`) to a `WHERE` clause + params,
  including the `service_presence` `EXISTS` subquery for `confirmed/synced/pending`.
- **FFI** (`cw-ffi/src/lib.rs`): `FieldStore.fetch_qsos_query(query,limit,offset)`,
  `qso_count_query(query)`, `qso_count()`, per-entity `fetch_*/count_*`. **Row
  projection + count only — no GROUP BY, no aggregate columns, no DISTINCT-count, no
  custom ORDER BY.**
- **Swift bridge**: `RustQSOReadSource: QSOReadSource, QSOQueryReadSource`
  (`count(query:)`, `page(query:limit:offset:)`); `CwStoreProvider` actor holds the
  single `FieldStore`; `CwFfi+Generated.swift` is the generated UniFFI binding.
- **Test pattern**: `cw-store/tests/query_corpus.rs` — load JSON QSO fixtures, run,
  assert result IDs vs golden. Analytics parity tests follow this shape.

### The gap

| Capability | Today | Needed |
|-----------|-------|--------|
| `WHERE` filter (DSL) | ✅ `compile_where` | reuse as-is |
| row projection / `COUNT(*)` | ✅ | reuse |
| `GROUP BY` + `COUNT`/`SUM`/`COUNT(DISTINCT)` | ❌ | **build** |
| dedup-by-`(callsign,band,mode)` (activation "unique QSOs") | ❌ | **build (parity-critical)** |
| custom `ORDER BY` / `LIMIT` on aggregates | ❌ | build |
| typed aggregate DTOs over FFI | ❌ | build |

---

## Design

### Principle: aggregate in SQL, return small DTOs

Do the `GROUP BY`/`COUNT`/`DISTINCT` **in SQLite inside cw-store**, returning a handful
of aggregate rows — never fetch-all-then-reduce in Rust or Swift. This is the whole
point: main-thread/actor cost becomes O(result rows), not O(QSOs), and the unbounded
`MyParksView` scan disappears. Reuse `compile_where` so every aggregate accepts an
optional `.cwquery` filter (e.g. band breakdown of `mode:ft8 after:2026-01-01`):

```
SELECT <group-expr> AS k, COUNT(*) AS n, COUNT(DISTINCT callsign) AS calls, ...
FROM qso
WHERE (<compiled DSL>) AND is_hidden = 0
GROUP BY k [ORDER BY ... ] [LIMIT ...]
```

Grouping expressions map to `cw-domain` so labels/order stay canonical:
`band` (ordered by `BAND_ORDER`), `ModeFamily::family(mode)`, `dxcc`→`COUNTRIES` name,
`SUBSTR(their_grid,1,N)` for grid tiles, `strftime` buckets for time series,
`(park, date(qso_date))` for activations.

### Catalog of typed primitives (recommended) vs. a general aggregate DSL

**Recommend a fixed catalog** of typed FFI functions, one per demand shape, over a
general "analytics query language." Rationale: each maps 1:1 to a consuming actor, is
trivially golden-testable, and avoids designing/securing an aggregate DSL now. Leave
room to generalize into a `.cwquery` aggregate extension later (a `group:band count:`
syntax) once the catalog stabilizes — note it, don't build it.

Initial catalog (new `cw-ffi` functions + `#[derive(uniffi::Record)]` DTOs):

| FFI fn | DTO | Serves |
|--------|-----|--------|
| `qso_distinct_counts(query)` | `{ qsos, bands, grids, entities, parks, confirmed }` | StatsComputationActor headline counts |
| `qso_count_by(query, dimension)` | `[{ key, label, count, distinct_calls }]` (dim ∈ band/mode_family/dxcc/state/month) | dashboard breakdowns, charts, map filter lists |
| `qso_grid_tiles(query, precision)` | `[{ tile, count, confirmed, last_qso }]` | GridOverlayDataActor |
| `was_summary(query)` | `{ per_mode: [{mode_family, states:[..]}], all_states:[..] }` | WAS / WAS-250, NeedsEngine WAS |
| `dxcc_worked(query)` | `[{ dxcc_id, name, lat, lon, count, bands:[..] }]` | DXCC needs, map entity rollup |
| `activation_rollup(query)` | `[{ park, date, unique_qsos, total_qsos, successful }]` (dedup `(call,band,mode)`) | POTAAwardsActor, MyParksView |
| `service_presence_counts(query)` | `[{ service, uploaded, pending }]` (dedupe qso_id) | AsyncServicePresenceCounts |
| `session_equipment_rollup(query)` | `[{ kind, name, sessions, qsos }]` | EquipmentStatsActor (groups **LoggingSession**) |

DTOs mirror existing `Ffi*` records; conversions live beside them. Wire each into
`FieldStore` (lock `inner`, run SQL) exactly like `fetch_qsos_query`.

### Swift seam: `AnalyticsReadSource` protocol, two impls, mode-gated

Mirror the read-cutover pattern in `CarrierWaveData/.../RustStore/`:

```
protocol AnalyticsReadSource {
    func distinctCounts(query: String) async throws -> DistinctCounts
    func countBy(query: String, dimension: Dimension) async throws -> [DimensionCount]
    func activationRollup(query: String) async throws -> [ActivationRollupRow]
    // … one per catalog entry
}
struct RustAnalyticsReadSource: AnalyticsReadSource  // FieldStore FFI
struct SwiftDataAnalyticsReadSource: AnalyticsReadSource  // today's actor logic, extracted
```

The dashboard/map/award actors call the protocol; `CwStoreQSOMode.current` selects the
backend (`on` → Rust, else SwiftData), same as the list reads. The existing actors keep
their SwiftData accumulators as the `SwiftDataAnalyticsReadSource` impl — that is both
the fallback and the **parity oracle**.

### Verification — the key advantage

These are `CarrierWaveData`-level read sources, so parity runs in the **package loop**,
not on a device:

- **Rust unit/parity** (`cw-store/tests/`): golden-fixture corpus per aggregate
  (`query_corpus.rs` shape) — diverse bands/modes/DXCC/grids/dupes → assert DTO rows.
- **Cross-impl parity** (`swift test`, CarrierWaveData): feed an in-memory SwiftData
  store and a cw-store seeded from the same fixtures; assert
  `RustAnalyticsReadSource` == `SwiftDataAnalyticsReadSource` for each function. This is
  the acceptance bar and it runs here in seconds (cf. the 28 green RustStore read tests).
- No `xc`/device gate, unlike the write seam.

---

## Decomposition (one slice ≈ one session; Rust-first, then Swift + parity)

Each slice: DTO + SQL + FFI fn → regenerate bindings → `RustAnalyticsReadSource` +
extract `SwiftDataAnalyticsReadSource` → cross-impl parity test → route the consumer
actor (shadow→on). Ordered by value × independence:

- **N0 — seam + distinct counts. ✅ DONE.** `qso_distinct_counts` + `AnalyticsReadSource`
  protocol / DTO conventions / cross-impl parity harness. (`AnalyticsAggregator` is the
  pure oracle; the parity test seeds plain QSO objects + cw-store, no `ModelContainer`.)
- **N1 — `qso_count_by`. ✅ DONE.** band / mode-family / dxcc / month breakdowns
  (mode-family via a `cw_mode_family` SQLite UDF; DXCC labels from `cw-domain`).
- **N2 — WAS + DXCC. ✅ DONE.** `was_summary` (valid-state set + `NORMALIZED_STATE` SQL
  mirroring `USStates.normalizeAbbreviation`, grouped per `cw_mode_family`) and
  `dxcc_worked` (count + lat/lon/name from `cw-domain`). Parity oracle ports the 50-state
  set into `AnalyticsAggregator`; DXCC parity compares id+count and asserts location
  separately (same split as `count_by(.dxcc)` labels). Routing → POTAAwardsActor+WAS250
  and NeedsEngine still TODO.
- **N3 — activation rollup. ✅ DONE.** `qso_activation_rollup(query, min_qsos)` at parity
  with POTAAwardsActor's group key + `UPPER(callsign)|band|mode` dedup. (MyParksView's
  per-park rollup, which kills its unbounded scan, is a sibling function — TODO.)
- **N4 — presence counts. ✅ DONE.** `service_presence_counts(query, primary_callsign,
  configured_services)` groups the `service_presence`↔`qso` join, deduped by `qso_id`:
  uploaded = distinct present QSOs/service; pending = distinct `needs_upload` QSOs limited
  to configured services + (when set) the primary callsign (empty callsign always matches).
  Only the hidden filter (no metadata exclusion), matching the Swift actor. Routing →
  AsyncServicePresenceCounts still TODO.
- **N5 — map/grid. ✅ DONE.** `qso_grid_tiles(query, precision)` (count + confirmed +
  last-QSO per uppercased grid prefix) → GridOverlayDataActor. Entity rollup served by
  `dxcc_worked`; state rollup added as `qso_state_counts` (per valid 50-state, count-desc).
- **N6 — session/equipment + brag sheet. ✅ DONE (first cut).** `session_equipment_rollup`
  (unpivots radio/antenna/key/mic over `logging_session`, `qso_count > 0`) +
  `session_combo_rollup` (rig+antenna) at parity with `EquipmentStatsActor`. `brag_period_metrics`
  ports the **SQL-trivial** brag subset (totals, CW/phone/digital, operating-days, distinct
  bands/callsigns/entities, QRP/milliwatt, parks-hunted, park-to-park, perfect-reports);
  distance / streak / per-session-window / new-this-period / activation-grouping metrics are
  intentionally deferred (per-row math — stay SwiftData-side; see out-of-scope).
- **MyParks per-park rollup. ✅ DONE.** `qso_park_rollup(query)` (activation days +
  hunt QSOs + last-worked, comma-split refs) at parity with `MyParksView.computeMyParkEntries` —
  retires its unbounded full-table scan once routed.

N0–N2 cover the dashboard (the most-seen surface); N3 + MyParks retire the perf violations.

---

## Risks / parity hot-spots

1. **Dedup semantics (N3).** "Unique QSOs per activation" and award counting dedupe by
   `(callsign, band, mode)` with **mode-family equivalence** (`cw-domain::ModeFamily`).
   The SQL must match Swift's dedup exactly, incl. NULL band/mode handling. Build the
   golden corpus from real edge cases (same call diff band; phone variants USB/LSB/SSB).
2. **Hidden / metadata exclusion.** Every aggregate must apply `is_hidden=0` AND the
   metadata-mode exclusion (`QSOMode.metadataModes` — WEATHER/SOLAR/NOTE), the single
   source of truth on the Swift side. Encode the same exclusion in SQL or the DSL prefix.
3. **DXCC derivation.** Stats use stored `dxcc` where present but may fall back to
   prefix derivation; `NeedsEngine` is grid-aware. Decide stored-vs-derived per aggregate
   and keep it identical across impls.
4. **Time zones.** Activation grouping is **UTC-date**; `strftime` must use UTC. POTA
   metadata modes already split at UTC midnight (see the LoggingSession split work).
5. **Float/string canonicalization.** `freq_khz` vs MHz, band-label casing — reuse the
   compiler's existing `cw_lower()` / MHz conventions so aggregate keys match list reads.

## Performance

SQL `GROUP BY` over existing indexes; add as needed (candidate composite/partial indexes:
`(is_hidden, qso_date)`, `(park, qso_date)` for activations, `(their_grid)`). Returns
≤ a few hundred rows. Eliminates the 500/batch full scans on the hot dashboard path and
the `MyParksView` load-all. Measure with a 100k-QSO fixture before/after per slice.

## Out of scope (explicitly)

- **Writes / the seam** — read-only; no `cwStore` write changes.
- **SwiftData removal** — the SwiftData impl stays as fallback + parity oracle; this is a
  read cutover, not the Phase-5 retirement.
- **A general aggregate query DSL** — catalog first; generalize later if warranted.
- **Equipment/brag-sheet deep stats beyond N6 first cut** — distance/efficiency/“fun”
  metrics can stay SwiftData-side until the catalog proves out.

## Effort

Multi-session, cross-language. Rough order-of-magnitude: N0 ~1 session (seam + harness),
N1–N5 ~1 session each, N6 larger. Rust portions verify with `cargo test` (~15 s);
cross-impl parity with `swift test` (seconds) — all in the fast loop, no device.

---

## Remaining work (handoff — 2026-06-20)

> **Update — 2026-06-21 (supersedes the routing/"slices left" notes below).** The
> first cut shipped, then the
> [analytics-models comprehensiveness audit](2026-06-21-analytics-models-comprehensiveness-audit.md)
> closed the gaps this design deliberately deferred. Net changes since 2026-06-20:
> - **New aggregates beyond N0–N6:** `pota_awards` (full POTAAwards port — replaces
>   the "was_summary serves POTAAwards" assumption), `was250`, `was_drilldown`
>   (per source×mode×state for `StatsComputationActor.wasData`). Each has a cw-ffi
>   DTO, a `RustAnalyticsReadSource` method, an `AnalyticsAggregator` oracle, and a
>   parity test.
> - **New reference table:** `pota_park` (**schema v4**, beyond the v3 the fidelity
>   audit planned) + a `cw_domain::us_grid_state` grid→state port, both feeding
>   `pota_awards`' `statesActivated`. Populated by a POTAParksCache write-through (iOS).
> - **Routing is now largely DONE, not pending:** StatsComputationActor (counts +
>   `wasData`), GridOverlayDataActor, MyParksView, EquipmentStatsActor,
>   AsyncServicePresenceCounts, and **POTAAwardsActor** all overlay cw-store under
>   `.on`. **Only `BragSheetComputationActor` remains unrouted.**
> - **Brag deep stats — scope reversal:** the "deferred to SwiftData by design" call
>   below is being **reversed** by the audit (distance UDF + streaks + geographic
>   rollups are now planned for Rust). See the audit's "Next steps."
>
> **For the current state + the single ordered next-steps list, see
> [rust-migration-status.md](rust-migration-status.md).**

**Done (verified in the package loop):** every read-source slice — N0–N6, the MyParks
per-park rollup, and the N5 state/entity follow-ons. The seam, the proven add-a-slice
recipe, and the parity harness all exist. To add a slice, repeat the recipe:

1. **cw-store** (`cw-store/src/analytics.rs`): add the result struct + an `impl Store`
   method running the `GROUP BY` SQL. Always start the WHERE with the `VISIBLE_QSO`
   const and `AND ({where_sql})` from `compile_where(query)` (reuse for the DSL filter).
   Add a `#[cfg(test)]` test using `base_qso()` + the `seed()` helper. Re-export the
   struct in `cw-store/src/lib.rs`.
2. **cw-ffi** (`cw-ffi/src/lib.rs`): add the `#[derive(uniffi::Record)]` DTO + `From`
   impl + a `FieldStore` method (parse query → lock inner → map). Enums: `uniffi::Enum`.
3. **Regenerate bindings:** `rust/cw-core/scripts/build-xcframework.sh` (~3 min; updates
   `CwFfi+Generated.swift` + the staged staticlib). Commit the regenerated `*.swift`.
4. **Swift** (`CarrierWaveData/.../RustStore/AnalyticsReadSource.swift`): add the DTO +
   a protocol method + the `RustAnalyticsReadSource` impl + the `AnalyticsAggregator`
   pure oracle (matching the SQL exactly). Add a parity case to `AnalyticsReadSourceTests`
   (build plain QSO objects, seed cw-store via `SwiftDataStoreImporter.project`, assert
   `RustAnalyticsReadSource` == `AnalyticsAggregator`). `swift test --filter
   AnalyticsReadSourceTests` from the package dir; `swiftformat` via `/opt/homebrew/bin`
   (the `~/.local/bin` one is a Linux binary — won't exec on macOS).

**Slices left:** none — all read-source aggregates are implemented. What was N6 / the
MyParks rollup / the N5 follow-on now exist as `session_equipment_rollup` +
`session_combo_rollup` + `brag_period_metrics` (first cut), `qso_park_rollup`, and
`qso_state_counts` (entity counts via `dxcc_worked`). The brag sheet's distance / streak /
window / new-this-period / activation-grouping metrics remain deferred to SwiftData by
design (see out-of-scope).

**Cross-cutting, still pending:**

- **Route the consuming app-target actors** onto `AnalyticsReadSource` (gated by
  `CwStoreQSOMode`). This is **app-target** work (StatsComputationActor, POTAAwardsActor,
  GridOverlayDataActor, …) — builds locally but full behavior is device-gated, like the
  write seam. Until routed, the new read sources are dormant (Rust is exercised only by
  the parity tests).
- **Batched SwiftData fallback** (`off`-mode `AnalyticsReadSource` conformer): must
  fetch in ≤1000-row batches (PERFORMANCE.md) and fold via `AnalyticsAggregator`. Added
  at routing time; the unbounded-fetch wrapper was intentionally dropped (perf gate).
- **Indexes:** add `(park, qso_date)` (activations) and `(their_grid)` (tiles) if a
  100k-QSO benchmark shows the `GROUP BY`s need them.

**Parity reminders (apply to every slice):** start WHERE with `VISIBLE_QSO`; dedupe with
the *exact* Swift key (raw band/mode, `UPPER(callsign)`); UTC for any date bucket;
case-sensitive `Set`-style distinct unless the Swift source uppercases.

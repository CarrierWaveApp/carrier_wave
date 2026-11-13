# Band Scope SQL Query Layer — Post-Workbench Roadmap

> Companion to the Query Workbench shipped on `claude/sql-query-band-scope-Q3Lhm`. The workbench compiles and runs but the tables it queries are mostly empty until producers wire up. This document orders the follow-up phases from "must do before users notice" through "speculative."

## Status (as of 2026-05-02)

**Shipped (v1, on workbench branch):**

- `CarrierWaveData/Query/` package — GRDB-backed `QueryStore` (writer) + `QueryReader` (read-only `DatabasePool` with `PRAGMA query_only`).
- v1 schema: `qsos`, `dxcc`, `polo_notes`, `dxcc_status` view, `meta`. Transient `scope.spots` / `scope.spot_observations` / `scope.spotters` in a cache-dir SQLite file deleted on launch.
- `.cwquery` JSON format + `cwquery://` URL codec + `SavedQueryStore` with hard-reject on schema-version mismatch.
- QSO write hooks at `CloudSyncEngine+Inbound`, `CloudSyncJournalEngine+Inbound`, `ParsedEntryView` (macOS).
- Spot ingestion at `SpotAggregator.mergeSpots` upstream of dedup so per-skimmer fan-out is preserved.
- `QuerySeedCoordinator` (5K-row batched seed with watermark delta sync).
- Query Workbench window (Cmd+Shift+Q) with editor, results grid, profile panel, save/import/share.
- 5 starter queries seeded on first launch.
- Tests: migration roundtrip, QSO mapping (metadata-mode filter), URL roundtrip, read-only enforcement.

**Out of v1 (this roadmap):** band scope filter consumption; iOS workbench; full data-source wiring (DXCC/polo/spotter location); polish (error offsets, profile tree, click actions); other-consumer migration (NaturalLanguageLogSearch, dashboard).

---

## Phase 6 — Make the workbench actually useful end-to-end

The workbench compiles but starter queries return zero rows for everything except `qsos`. Five wiring tasks turn empty tables into useful data.

### 6.1 DXCC seed

- **File:** `swift/macos/CWSweep/Services/DXCC/DXCCLookupService.swift`
- **Change:** after `loadCTY()` succeeds, walk `CTYDatabase.entities` → `[DXCCRow]` → `await QueryFacade.current?.seedDXCC(...)`. Idempotent — `seedDXCC` already does `DELETE` + `INSERT`.
- **Why:** unlocks every "from EU" / "in zone 33" / `dxcc_status` query.

### 6.2 Polo notes seed + change push

- **File:** `swift/macos/CWSweep/Services/Spots/PoloNotesStore.swift`
- **Change:** on `forceRefresh()` and on every `setInfo`/`removeInfo`, push affected callsigns to `QueryStore.upsertPoloNote` / `deletePoloNote`. Subscribe to KVS change notifications via existing `NSUbiquitousKeyValueStore.didChangeExternallyNotification` hook.
- **Why:** `note:good_op`-style queries; user-tagged callsigns become first-class filterable data.

### 6.3 Spotter location backfill (free tier only)

- **File:** `swift/macos/CWSweep/Services/Spots/SpotObservationMapper.swift`
- **Change:** when constructing a `SpotterRow` and `spot.spotterGrid == nil`, look up the spotter's prefix in `CTYDatabase` and fill `dxcc_entity`, `continent`, `lat`, `lon` from the entity centroid.
- **Defer:** lazy HamDB lookup tier; bundled RBN skimmer roster JSON. Both add complexity and only matter if the entity-centroid pass proves insufficient.
- **Why:** "spots heard by EU skimmers" doesn't work until spotter rows have a continent.

### 6.4 Scope pruning timer

- **File:** `swift/macos/CWSweep/CWSweepApp.swift`
- **Change:** add a `Timer.publish(every: 60).autoconnect()` on the workspace `.task` modifier that calls `await queryStore?.pruneScope(window: 30 * 60)`.
- **Why:** without this, observations accumulate forever. The transient scope file already deletes on launch but a long session still grows unbounded.

### 6.5 QSO seed bootstrap timing

- **File:** `swift/macos/CWSweep/CWSweepApp.swift`
- **Change:** move `querySeedCoordinator?.seedIfNeeded()` from the workbench window's `.task` to the workspace `.task` so the seed starts at app launch rather than first workbench open. Add a "Indexing N QSOs…" banner inside the workbench when `querySeedCoordinator.state == .seeding`.
- **Why:** users opening the workbench shouldn't wait minutes for the seed; better to start it eagerly and surface progress.

**Phase 6 is a hard prerequisite for everything below.** Without it, "starter queries" are misleading; users will assume the workbench is broken.

---

## Phase 7 — Band scope consumption (the original ask)

The user's first message: "I want to add a mode to band scope that does this." This is when SQL becomes a band scope filter.

### Surface

- New `BandScopeFilterMode` enum in `swift/macos/CWSweep/Models/Spots/BandScopeFilterConfig.swift`: `.widgets` (today's UI), `.savedQuery(UUID)`. Persist via `@AppStorage`.
- `BandScopeFilterBar` shows either the existing source/region/status toggles (when `.widgets`) or a "Query: <name> ▾" picker showing the `SavedQueryStore` list (when `.savedQuery`).
- `BandMapView` reads the selected query, runs it through a GRDB `ValueObservation` against `scope.spots.spot_id` debounced to 500ms, and uses the resulting `Set<String>` to filter which `EnrichedSpot`s are drawn.

### Constraints

- Query must select a `spot_id` column. Validate at picker time using `sqlite3_stmt_readonly` + column-name introspection. Reject with a clear error in the picker rather than silently rendering empty.
- Failure to run the query falls back to "show all spots" with a red banner — never a blank scope.

### Files

- `Models/Spots/BandScopeFilterConfig.swift` — mode enum + selected query ID storage
- `Views/Spots/BandScopeFilterBar.swift` — picker UI
- `Views/Spots/BandMapView.swift` — `ValueObservation` plumbing
- `Views/Spots/BandMapView+Drawing.swift` — apply filter set during render

Estimated ~250 lines.

---

## Phase 8 — Polish the workbench

Things users will hit and bounce off without these.

### 8.1 Error offset highlight

- **Problem:** `QueryError.errorOffset` is always nil. GRDB doesn't expose `sqlite3_error_offset`.
- **Fix:** when a prepare fails, fall through to raw `sqlite3` via `db.sqliteConnection` to read `sqlite3_error_offset(handle)`. Render as a red caret in `QueryEditorView`.
- **File:** `swift/packages/CarrierWaveData/Sources/CarrierWaveData/Query/QueryReader.swift`.

### 8.2 Profile tree rendering

- **Problem:** the profile panel shows raw `EXPLAIN QUERY PLAN` rows as a flat list.
- **Fix:** indent by parent ID column to show the actual plan tree.
- **File:** `swift/macos/CWSweep/Views/Query/QueryWorkbenchView.swift` (`profileSummary`).

### 8.3 Click actions on result cells

- **Problem:** `QueryResultsView` cells are inert.
- **Fix:** detect known column names — `spot_id` → "Tune" via `RadioManager.tuneToSpot`; `callsign` → HamDB popover via existing `SpotDetailInspector`. Right-click → copy.
- **File:** `swift/macos/CWSweep/Views/Query/QueryResultsView.swift`.

### 8.4 Three more starter queries

- Plan called for 8; v1 ships 5. Add: needed-DXCC-on-band, EU greyline mults, callsigns-I've-never-seen.
- **File:** `swift/macos/CWSweep/Views/Query/StarterQueries.swift`.

### 8.5 Cancel running query

- **Problem:** GRDB queries are synchronous on the actor; long ones hang the workbench.
- **Fix:** expose `sqlite3_interrupt` on the read-only connection. Add a "Stop" button visible while `isRunning`.
- **File:** `QueryReader.swift` + `QueryWorkbenchView.swift`.

### 8.6 Result row limit affordance

- **Problem:** today's hard 5K limit is silent except for a "(truncated)" label.
- **Fix:** "showing 5000 of N — show more" button that re-runs with double the limit.
- **File:** `QueryResultsView.swift`.

---

## Phase 9 — iOS adoption

Everything in `CarrierWaveData/Query/` is platform-agnostic. iOS needs three small pieces.

### 9.1 iOS seed coordinator

- **File:** `swift/ios/CarrierWave/Services/Query/QuerySeedCoordinator.swift`
- Same shape as macOS but with **1K-row batches** per CLAUDE.md iOS limit, and serialized with other full-table scans (`StatsComputationActor`, `MapDataLoadingActor`) to avoid concurrent OOM on 4 GB devices.

### 9.2 iOS workbench view

- **File:** `swift/ios/CarrierWave/Views/Query/QueryRunnerView.swift`
- Probably **not** a SQL editor on a phone screen. Instead: starter library + saved queries from iCloud Drive + Run button. Authoring stays macOS-only. Phone is a runner.

### 9.3 URL scheme

- **File:** `swift/ios/CarrierWave/Info.plist` — register `cwquery://` like macOS does.
- **File:** `CarrierWaveApp.swift` — `.onOpenURL` handler routes to `QueryRunnerView`.

### 9.4 Experimental gating

- **File:** `swift/packages/CarrierWaveData/Sources/CarrierWaveData/Utilities/ExperimentalFeature.swift`
- Add `.queryRunner` (alpha, `isHiddenByDefault = true`) so the surface is opt-in until validated on device.

---

## Phase 10 — Replace existing consumers

The whole reason the schema lives in `CarrierWaveData` was reuse. Three feature areas converge on one data path.

### 10.1 NaturalLanguageLogSearch → SQL builder

- **File:** `swift/macos/CWSweep/Services/AI/NaturalLanguageLogSearch.swift`
- Today: pattern matchers parse "20m CW from EU last week" into a `LogSearchQuery` struct, then run a `FetchDescriptor`. Replace with a SQL builder that emits `WHERE band='20m' AND mode='CW' AND continent='EU' AND timestamp > ?`. Existing parser stays; only the executor changes.
- **Win:** indexed lookup against pre-joined `dxcc` data. Order-of-magnitude faster on large logs.

### 10.2 Dashboard / stats

- **Files:** `swift/macos/CWSweep/Views/Dashboard/DashboardView.swift`, `swift/packages/CarrierWaveData/Sources/CarrierWaveData/.../StatsComputationActor.swift`
- Today: `StatsComputationActor` walks QSOs in 1K batches, deduplicates by UUID (CloudKit dedup workaround), aggregates in Swift. SQLite aggregates do this in one query, no batches, no Swift-side dedup (`COUNT(DISTINCT id)`).

### 10.3 WAS / WAZ / grid trackers

- **Files:** `swift/packages/CarrierWaveData/Sources/CarrierWaveData/.../WASTracker.swift` and `WAZTracker.swift`
- Today: hand-rolled aggregation over fetched QSOs. Replace with `GROUP BY state` / `GROUP BY cq_zone` queries. The `dxcc_status` view already covers most of this; the trackers become thin wrappers.

This is the phase where the SQL layer pays off architecturally — three feature areas converge, and we delete more code than we add.

---

## Phase 11+ — Speculative

Only ship if real-world signal demands.

### Schema v2

Add columns to `qsos` (RST sent/received, name, contest fields) once we know what users actually query. Migration adds columns + reseeds via watermark reset. Touches `Schema/Migrations.swift`, `QSORow.swift`, `QSOMapper.swift`.

### Reactive saved queries

Use GRDB `ValueObservation` to power "live" workbench results that refresh as data changes. Useful for "current rate" / "active spots" panels embedded outside the workbench (status bar widgets, Phase 7 band scope).

### Community query library

Curated `.cwquery` files served via the activities server with an in-app browser (similar to existing contest-definitions infrastructure). The `cwquery://` URL scheme already supports it.

### Historical observations ledger

A persistent downsampled `observations_history` table — append one row per spot per minute, retain 7 days. Answers "what was propagation like last Tuesday?" Out-of-scope for the live scope but a natural extension. Adds one migration.

### Activity server queries

Server-side query exchange — run a saved query against a public/aggregate data set on the activities server (with privacy controls). Speculative.

---

## Sequencing notes

- **Phase 6 is mandatory** before any user can see useful results. Without it the workbench looks broken.
- **Phase 7 closes the loop with the original product ask.** It's the demo that justifies the whole layer to a user who didn't follow the architecture discussion.
- **Phase 8 + 9 + 10 are independent** and can interleave. Pick by user signal: if power users complain about authoring UX → 8; if iOS users want it → 9; if the dashboard is slow → 10.
- **Phase 11 is purely speculative** — do not start without a specific user story.

## Verification per phase

| Phase | Verification |
|------:|-------------|
| 6 | Open workbench → "DXCC status snapshot" returns >0 rows; "Top spotters last hour" returns names with continents; pruning visible in `scope_observations` count after an hour |
| 7 | Pick a saved query in `BandScopeFilterBar` → only matching spots render in `BandMapView`; switch back to `.widgets` → filter restored |
| 8 | Type intentionally bad SQL → red caret on offending column; click `spot_id` cell → radio tunes; "Stop" interrupts a CTE-bomb |
| 9 | iOS app: tap a starter query → results appear; receive shared `cwquery://` link → import flow runs |
| 10 | NL search "EU CW last week" runs in <50ms on a 100K log; dashboard initial load drops from seconds to <100ms |

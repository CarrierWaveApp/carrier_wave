# QSO Rust-Store Cutover — Sub-project C Handoff

**Date:** 2026-06-16
**Branch:** `main`
**Companion docs:** [C design](2026-06-16-qso-cutover-C-design.md) · [B handoff](2026-06-16-qso-cutover-B-handoff.md) · [cutover design/spec](2026-06-14-qso-rust-store-cutover-design.md) · [A handoff](2026-06-14-qso-cutover-handoff.md)

The "what shipped / what's next" doc for sub-project C — the Logbook list now renders
from unified QSO snapshots, routed by `cwStoreQSOMode`.

---

## TL;DR

**Sub-project C is DONE.** `LogsListContentView` renders a backend-agnostic
`QSORowSnapshot` from a `LogbookSnapshotSource`. In `off`/`shadow` the source is
SwiftData (behavior-identical to the pre-cutover list); in `on` it is the Rust
cw-store query path (`RustQSOReadSource`). `QSORowSnapshot` was widened to carry every
field the row cell + badges need, including a `[PresenceSummary]` projected from the
Rust query (one batched `service_presence` join) or derived from `qso.servicePresence`
on the SwiftData side. Writes and the detail screen stay on SwiftData via an id-bridge;
`on` mode runs a `CwStoreMirror.drain()` read-after-write barrier before re-paging.

SwiftData remains the system of record. The Rust store is still a read mirror, gated
behind the same hidden, off-by-default `cwStoreQSOMode` experiment from A/B.

Cutover progress: **A** ✅ (infra + count), **B** ✅ (query compiler + ServicePresence
mirror), **C** ✅ (this — the Logbook list). Remaining: write-cutover, non-QSO
entities, stats/map reads, deleting SwiftData, macOS Sweep.

## What shipped in C

**Rust / FFI**
- `cw-store/service_presence.rs` — `fetch_service_presences_for_qsos(&[String])`: batched
  `WHERE qso_id IN (...)` presence fetch (empty input → empty). Unit-tested.
- `cw-ffi/src/lib.rs` — `FfiQso.presence: Vec<FfiServicePresence>`; `fetch_qsos_query`
  projects presence onto the page by grouping the batched fetch by `qso_id`. New FFI test
  `fetch_qsos_query_projects_presence`. `FfiServicePresence` (entities) gained `Default`.
- `cw-store/tests/query_corpus.rs` — `presence_projection_matches_fixture` asserts the
  projection matches the shared fixture over the whole corpus dataset.
- Regenerated `CwFfi.xcframework` + `CwFfi+Generated.swift` (presence reaches Swift).

**Swift — data layer**
- `CarrierWaveData/RustStore/QSORowSnapshot.swift` — widened (frequency MHz, rstSent,
  theirGrid, parkReference, name, power, state, lotwConfirmed, qrzConfirmed) + new
  `PresenceSummary`; `init(ffi:)` maps the projected presence.
- `CarrierWave/Views/Logs/QSORowSnapshot+FromQSO.swift` — app-target `init(qso:)` mapper
  (id = `SwiftDataStoreImporter.uuid(qso.id)`, presence from `qso.servicePresence`).

**Swift — view layer** (all under `swift/ios/CarrierWave/Views/Logs/`)
- `LogbookSnapshotSource.swift` — protocol + `SwiftDataLogbookSource` (batch-window,
  `paginatesFilteredFully == false`) + `RustLogbookSource` (full pagination, `== true`).
- `LogbookIDBridge.swift` — snapshot id → live `QSO` (`fetchQSOs`/`fetchQSO`) + the
  `QSODetailLoader` navigation destination.
- `QSORow.swift` — row cell + `ServicePresenceBadge`, rendered from the snapshot (+ a
  `QSORow(qso:)` convenience for the day-summary preview and a `ServicePresenceBadge`
  convenience for the QSO detail view, both of which still hold live models).
- `LogsListView.swift` / `LogsListDataLoading.swift` / `LogsListDateSections.swift` /
  `LogsListView+BulkDelete.swift` / `LogsListView+GroupSession.swift` /
  `LogsListView+Toolbar.swift` — state → `[QSORowSnapshot]`, selection → `Set<String>`,
  grouping over snapshots, source-routed pagination, id-bridged writes, drain barrier.
- `CwStoreMirror.swift` + `CarrierWaveApp.swift` — `CwStoreMirrorRegistry.current`
  (`@MainActor` weak handle) so the list can `drain()` in `on` mode.

**Tests**
- `QueryParityTests.swift` (the acceptance gate) — extended to assert presence-summary
  parity between the SwiftData mapper and the Rust projection over the shared fixture.

## How to exercise it

Enable the hidden **"QSO Rust Store"** experiment (Settings → Experiments), then set the
mode in Data Migration:
- `off` — today's SwiftData list (default).
- `shadow` — still SwiftData for rendering; the mirror dual-writes. Use the existing
  **Run QSO Parity Check** / **Run Saved-Query Parity Sweep** actions to compare paths.
- `on` — the Logbook serves from the Rust store. Filtered search now supports "Load More"
  over the whole match set; deletes/group/detail round-trip through SwiftData with a
  mirror drain before the list refreshes.

## Decisions worth remembering

1. **`contactCount` always reads SwiftData**, in every mode — it is a cheap per-callsign
   count against the system of record and is identical across backends (`QSORow` keeps its
   own `@Environment(\.modelContext)` count). The source protocol does not carry it.
2. **Shadow renders from SwiftData, identical to `off`.** No automatic per-page compare
   (perf rule); parity comparison stays the explicit Data Migration sweep/probe.
3. **`paginatesFilteredFully` is derived from the mode** (`qsoMode == .on`) so the view
   knows synchronously whether to show "Load More" for filtered queries.

## Watch list / known seams

- **Saved-Query Parity Sweep was NOT extended for presence drift.** The deterministic
  `QueryParityTests` presence assertion is the acceptance gate; the runtime sweep still
  only classifies row-set/count drift. Extending the package's public `QueryParityResult`
  for per-row presence is a reasonable follow-up but was deliberately out of scope (higher
  risk than the deterministic test warrants).
- **`CwFfi.xcframework` is gitignored.** The new `FfiQso.presence` only reaches Swift
  after `rust/cw-core/scripts/build-xcframework.sh` runs. Xcode Cloud / other machines
  must rebuild it.
- **Rust query calls run off-main automatically** (nonisolated `async` on the value-type
  `RustQSOReadSource`), so the `@MainActor` source protocol does not block the main thread.
  If a future change makes those calls actor-isolated, re-check for main-thread stalls on
  large logs (PERFORMANCE.md).
- **`QSODetailLoader` fetches the QSO lazily by id** on navigation. A snapshot whose QSO
  was deleted between render and tap shows a "QSO Unavailable" placeholder rather than
  crashing.
- **Pre-existing, unrelated:** `QuickEntryTimeTests` ("Bare HHMM accepted as time…") fails
  in `test-core` independent of this work (HHMM-vs-frequency parsing). Not touched here.

## Next steps (still out of scope)

1. The **write-cutover** — retire SwiftData as system of record; once writes go to
   cw-store, the id-bridge and the drain barrier collapse away.
2. `QSODetailView` / `QSOEditSheet` rendering from snapshots (still take a live `QSO`).
3. Non-QSO / non-ServicePresence entities; stats / map / aggregation reads; deleting
   SwiftData; macOS Sweep wiring.

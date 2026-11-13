# QSO Rust-Store Cutover — Sub-project C Design (Logbook list)

**Date:** 2026-06-16
**Branch:** `main`
**Companion docs:** [cutover design/spec](2026-06-14-qso-rust-store-cutover-design.md) · [B handoff](2026-06-16-qso-cutover-B-handoff.md) · [B design](2026-06-15-qso-cutover-B-query-compiler-design.md) · [A handoff](2026-06-14-qso-cutover-handoff.md)

Sub-project C refactors the Logbook list (`LogsListContentView`) to render from
**unified QSO snapshots** produced by either backend, routed by the existing
`cwStoreQSOMode` experiment. SwiftData stays the system of record; the Rust store
remains a read mirror. This is the read-cutover for the Logbook view only.

---

## Goal

Today `LogsListContentView` renders live SwiftData `QSO` objects and their
`servicePresence` relationship. C makes the list render `[QSORowSnapshot]` from a
`LogbookSnapshotSource` that has two implementations (SwiftData / Rust), selected by
`cwStoreQSOMode`. Writes (delete, group-into-session, edits from detail) continue to
go to SwiftData, bridged from the snapshot's string `id`.

## Decisions (locked during brainstorm)

1. **Unify on snapshots.** Both backends produce `QSORowSnapshot`; the SwiftData path
   maps `QSO → QSORowSnapshot` too. The view has **one** render path. This is the
   shape the eventual write-cutover wants.
2. **Project presence from Rust.** Each snapshot carries a `[PresenceSummary]` so the
   per-service badges render without a live `ServicePresence` relationship. The Rust
   query projects presence; the SwiftData mapper derives it from `qso.servicePresence`.
3. **One combined spec** (this doc) covering the data-layer widening and the view
   refactor.
4. **Shadow renders from SwiftData, identical to `off`.** The mirror still dual-writes
   in `shadow`; parity comparison stays the explicit Data Migration sweep / probe — the
   list does **not** auto-compare per page (perf rule: QSO count must never affect UI
   responsiveness).

## Architecture

### 1. `QSORowSnapshot` widening (`CarrierWaveData/RustStore/QSORowSnapshot.swift`)

Widen to carry every field `QSORow` reads. New fields:

| Field | Type | Source (FfiQso) | Source (QSO) |
|---|---|---|---|
| `frequency` | `Double?` (MHz) | `freqKhz / 1000.0` | `qso.frequency` |
| `rstSent` | `String?` | `rstSent` | `qso.rstSent` |
| `theirGrid` | `String?` | `theirGrid` | `qso.theirGrid` |
| `parkReference` | `String?` | `park` | `qso.parkReference` |
| `name` | `String?` | `name` | `qso.name` |
| `power` | `Int?` | `power` | `qso.power` |
| `state` | `String?` | `state` | `qso.state` |
| `lotwConfirmed` | `Bool` | `lotwConfirmed` | `qso.lotwConfirmed` |
| `qrzConfirmed` | `Bool` | `qrzConfirmed` | `qso.qrzConfirmed` |
| `presence` | `[PresenceSummary]` | batched SP query (§2) | `qso.servicePresence` |

Existing fields (`id`, `callsign`, `band`, `mode`, `timestamp`) are retained.

`PresenceSummary` (new, `Sendable`, `Equatable`, in the same file):

```swift
public struct PresenceSummary: Sendable, Equatable {
    public let serviceTypeRawValue: String
    public let isPresent: Bool
    public let isSubmitted: Bool
    public let needsUpload: Bool
}
```

`frequency` is stored in **MHz** to match `QSO.frequency` and `FrequencyFormatter`
(the B handoff freq-units bug: `freq_khz` is kHz; divide by 1000).

### 2. Rust presence projection (`cw-store/query` + `cw-ffi`)

`fetch_qsos_query` returns the page of QSO rows as today. **After** the page is
materialised, run one batched query:

```sql
SELECT qso_id, service_type_raw_value, is_present, is_submitted, needs_upload
FROM service_presence
WHERE qso_id IN (<page qso ids>)
```

Group rows by `qso_id` and attach to each `FfiQso` as a repeated nested
`FfiServicePresence`. A second batched query (not a JOIN) avoids row fan-out and keeps
the WHERE-lowering from B untouched. Empty `IN ()` is guarded (skip the query when the
page is empty).

`FfiServicePresence` (new UniFFI record): `{ service_type_raw_value: String,
is_present: bool, is_submitted: bool, needs_upload: bool }`. Add
`presence: Vec<FfiServicePresence>` to `FfiQso`. Regenerate `CwFfi.xcframework` +
bindings via `rust/cw-core/scripts/build-xcframework.sh` (gitignored artifact — must be
rebuilt on other machines / Xcode Cloud).

`count_query` is unchanged (count does not need presence).

### 3. SwiftData → snapshot mapper (app target)

`QSORowSnapshot(qso: QSO)` initialiser (app target, since it needs the `QSO` model).
Maps scalars directly and derives `presence` from `qso.servicePresence`:

```swift
presence = qso.servicePresence.map {
    PresenceSummary(serviceTypeRawValue: $0.serviceTypeRawValue,
                    isPresent: $0.isPresent,
                    isSubmitted: $0.isSubmitted,
                    needsUpload: $0.needsUpload)
}
```

This runs on the main actor inside the existing fetch path; presence is already faulted
because today's `QSORow` reads it. No new fetch cost.

### 4. `LogbookSnapshotSource` protocol (app target)

```swift
protocol LogbookSnapshotSource: Sendable {
    func page(query: String, limit: Int, offset: Int) async throws -> [QSORowSnapshot]
    func count(query: String) async throws -> Int
    func contactCount(callsign: String) async throws -> Int
    var paginatesFilteredFully: Bool { get }
}
```

- **`SwiftDataLogbookSource`** — wraps today's `BoundedDescriptor` fetch +
  `QueryCompiler` predicate/filter, maps results to snapshots. `paginatesFilteredFully
  = false` (retains the batch-window behavior for complex filtered search, so the `off`
  path is behavior-identical to today). `contactCount` = today's `boundedCount`.
- **`RustLogbookSource`** — wraps `RustQSOReadSource.page/count`. `paginatesFilteredFully
  = true` (Rust filters the whole table, so filtered search now supports Load-More — the
  intended improvement).

**`contactCount` always reads SwiftData**, in every mode. It is a cheap per-callsign
`boundedCount` against the system of record (excludes hidden + metadata modes) and is
independent of which backend drives the list. This guarantees the contact-count badge is
identical across modes and avoids a new Rust count path. Both source impls take a
`ModelContext` (or a shared count closure) solely for this.

Empty `query` means "all non-hidden, newest first" — the Logbook base predicate
(`is_hidden = 0`, `ORDER BY qso_date DESC`), matching B exactly.

The view selects the source from `cwStoreQSOMode`: `off`/`shadow` → SwiftData,
`on` → Rust.

### 5. View refactor (`LogsListContentView` + extensions)

- `@State var qsos: [QSO]` / `cachedFilteredQSOs: [QSO]` → `[QSORowSnapshot]`.
- `groupedByDate` walks snapshots (`timestamp` already present); `DateSection.qsos`
  becomes `[QSORowSnapshot]`.
- `QSORow(qso:)` → `QSORow(snapshot:)`; reads scalar fields + `presence`. Async caches
  (`POTAParksCache` by `parkReference`, `CallsignNotesCache` by `callsign`) and the
  total-contact-count badge stay, keyed off snapshot fields and the source's
  `contactCount`.
- `ServicePresenceBadge(presence: ServicePresence, qso: QSO)` →
  `ServicePresenceBadge(summary: PresenceSummary, lotwConfirmed: Bool, qrzConfirmed: Bool,
  isServiceConfigured: Bool)`.
- **Selection:** `Set<PersistentIdentifier>` → `Set<String>` (snapshot `id`).
  `List(selection:)` tags use `snapshot.id`; Select-All maps snapshot ids.
- **id-bridge (writes):** swipe-delete, bulk-delete, group-session, and detail-nav
  resolve the selected string id(s) → `FetchDescriptor<QSO>(predicate: #Predicate {
  ids.contains($0.id.uuidString) })` → run the **existing** `softDeleteQSOs` / grouping
  / `QSODetailView(qso:)` → `save()` → notify. The spotlight deep-link path already does
  exactly this id→QSO fetch; reuse the pattern.
- **Pagination:** Load-More and search both call `source.page(query:offset:)`,
  accumulate across pages, regroup. The Load-More affordance is shown when
  `loaded.count < count(query:)`. In the SwiftData source, complex filtered search keeps
  its single batch (`paginatesFilteredFully == false`) — Load-More is hidden for those,
  exactly as today.

### 6. read-after-write barrier

After any SwiftData write, the list re-pages. In `on` mode the re-page must
`await mirror.drain()` first (the mirror observes the SwiftData save and applies to
cw-store; `drain()` already exists on `CwStoreMirror` and `CwStoreMirrorActor`).
`off`/`shadow` re-page directly from SwiftData (already consistent). The
`.didLogQSO` / `.didSyncQSOs` notification handlers gain the same drain-in-`on` barrier.

### 7. Tests / parity

- Extend the shared query corpus (`rust/cw-core/cw-store/tests/fixtures/`) so the golden
  includes per-QSO presence summaries; assert the Rust projection matches.
- Extend `QueryParityTests` (the acceptance gate) to compare presence summaries between
  the SwiftData mapper and the Rust projection for the corpus queries.
- Extend the Saved-Query Parity Sweep classifier (`SavedQueryParitySweepAction`) to flag
  presence drift in addition to row-set drift.

## File-size / split plan

`LogsListView.swift` (339) and `LogsListHelperViews.swift` (478) are near the 500-line
cap. New files:

- `swift/ios/CarrierWave/Views/Logs/LogbookSnapshotSource.swift` — protocol + both impls.
- `swift/ios/CarrierWave/Views/Logs/QSORowSnapshot+FromQSO.swift` — the app-target mapper.
- `QSORow` moves to its own `swift/ios/CarrierWave/Views/Logs/QSORow.swift` if
  `LogsListHelperViews.swift` would exceed 500 after the refactor.

Update `swift/ios/.../FILE_INDEX.md` (iOS views index) for new/moved files.

## Out of scope (unchanged this slice)

Write-cutover (retiring SwiftData as system of record); `QSODetailView` rendering from
snapshots (still takes a live `QSO` via id-bridge); non-QSO / non-ServicePresence
entities; stats / map / aggregation reads; deleting SwiftData; macOS Sweep.

## Risks / watch list

- **xcframework rebuild** — the new `FfiServicePresence` only reaches Swift after
  `build-xcframework.sh` runs (gitignored artifact).
- **Default path regression** — `off` must stay behavior-identical. The SwiftData source
  keeps the exact `BoundedDescriptor` + batch-window semantics; only the in-memory
  representation handed to the view changes.
- **Presence ordering** — `sortedPresence` collapses per service type and sorts by
  `serviceType.rawValue`; the snapshot must preserve enough to reproduce this regardless
  of backend row order. The dedup/sort stays in the view, fed by `[PresenceSummary]`.
- **Empty `IN ()`** — guard the batched presence query against an empty page.

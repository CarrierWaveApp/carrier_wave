# QSO Rust-Store Cutover (Pilot Slice) — Design

**Date:** 2026-06-14
**Status:** ✅ Complete — all three sub-projects shipped (A 2026-06-14, B 2026-06-15, C 2026-06-16)
**Phase:** 4 (consumer cutover — first slice)
**Companion docs:** [rust-core handoff](../../plans/2026-06-13-rust-core-handoff.md) · [importer design](../../plans/2026-06-14-swiftdata-import-design.md)

---

## Goal

Prove the SwiftData → Rust `cw-store` **consumer cutover** pattern end-to-end on the
highest-value entity (QSO), behind an off-by-default experiment, without changing
the system of record. SwiftData stays authoritative for this entire slice; the
Rust store is a *mirror* we read from only when explicitly switched.

Success = on a real device we can: enable `shadow`, run a parity sweep with **zero
mismatches**, flip to `on` and see the Logbook list + QSO count served from the
Rust store identically, and flip back to `off` as instant rollback.

This is the first slice of the months-long cutover epic. Subsequent entities and
read surfaces reuse the seams built here.

## Locked decisions (this review)

- **Pilot entity:** QSO (the logbook core; read almost everywhere).
- **Sync strategy:** dual-write + flagged reads (strangler-fig). SwiftData writes
  are mirrored into the Rust store; reads switch behind a flag; cutting SwiftData
  writes is **out of scope** this slice.
- **Write hook:** a dedicated `ModelContext.didSave` observer (`CwStoreMirror`),
  independent of `CloudSyncJournalEngine` so the mirror updates on every local
  save regardless of whether iCloud sync is enabled.
- **Read shim scope:** Logbook list (paginated, filtered) + total QSO count only.
  Aggregations / map / complex-predicate reads stay on SwiftData this slice.

## Architecture

Three new units plus one tri-state flag, all behind a hidden experiment:

```
ExperimentalFeature.rustStoreQSO (hidden)  +  @AppStorage cwStoreQSOMode: off|shadow|on
        │
        ├─ CwStoreMirror (write path)
        │     observes ModelContext.didSave (object: nil → all contexts),
        │     filters to QSO, projects inserts/updates → FfiQso upsert and
        │     deletes → delete_qso, on a serial background actor.
        │
        ├─ QSOReadSource (read path) — a seam the Logbook list + count call
        │     off    → SwiftDataQSOReadSource (FetchDescriptor<QSO>, today)
        │     shadow → SwiftData authoritative + Rust read in background → probe
        │     on     → RustQSOReadSource (fetch_qsos / qso_count)
        │
        └─ QSOParityProbe (verification)
              compares count + ordered ids + field checksum; logs first-N
              divergences to the in-app diagnostics surface.
```

Each unit is independently testable: `CwStoreMirror` (write capture),
`QSOReadSource` (read routing), `QSOParityProbe` (verification). The Rust store is
already seeded by the existing importer; the mirror keeps it fresh from the moment
it is enabled. Same `cw-store.db` (App Group) and device-local SQLCipher key the
importer established.

## Write path — `CwStoreMirror`

A long-lived service observing `ModelContext.didSave` via NotificationCenter with
`object: nil`, so saves from background actor-contexts are captured too (not just
`mainContext`). On each save it reads `inserted` / `updated` / `deleted`
(`Set<PersistentIdentifier>`), filters to `QSO`, and dual-writes to `cw-store`.

**Deletes.** At `didSave` a deleted object is gone, so only its
`PersistentIdentifier` is available — not its `QSO.id` (the Rust PK). The mirror
also observes `willSave`; for objects about to be deleted it captures
`PersistentIdentifier → QSO.id` into an in-memory map, consumed in `didSave` to
call the new FFI `delete_qso(id)`. (This is why `delete_qso` + `notify(.Delete)`
is added to `cw-ffi` in this slice.)

**Off the save path.** The observer must not block `save()` with synchronous FFI
calls — batch imports save thousands of QSOs at once. It captures changed ids
synchronously, then hands them to a **serial background actor**
(`CwStoreMirrorActor`) that fetches those QSOs by id, projects to `FfiQso` in
bounded batches, and upserts. Serial = ordered writes; off-main = no UI hang.
Reuses the importer's existing `project(_:)` and batched-fetch helpers.

**Freshness on enable.** Enabling `shadow` runs a strict sequence so no write is
missed: **(1) start the mirror observing → (2) run the idempotent reconcile import
(existing importer) → (3) begin parity reads.** Starting the observer first means
any concurrent write is captured; the idempotent seed covers everything prior. The
`cwStoreImportCompletedVersion` marker gates redundant reseeds.

Scope: QSO only — the observer ignores other entities this slice.

## Read path — `QSOReadSource`

The Rust QSO query API is bounded: `qso_count()` and
`fetch_qsos(filter{callsign_prefix, band, mode, since}, limit, offset)`. The seam
exposes only what that can serve:

```swift
protocol QSOReadSource {
    func count(filter: QSOQueryFilter) async throws -> Int
    func page(filter: QSOQueryFilter, limit: Int, offset: Int) async throws -> [QSOSnapshot]
}
```

- `SwiftDataQSOReadSource` — today's `FetchDescriptor<QSO>` path; returns the
  existing `Sendable` snapshot the Logbook already uses.
- `RustQSOReadSource` — `fetch_qsos`/`qso_count`; maps `FfiQso → QSOSnapshot`.
- `RoutingQSOReadSource` — picks by `cwStoreQSOMode`: `off`→SwiftData;
  `shadow`→SwiftData result returned, Rust read run concurrently → `QSOParityProbe`;
  `on`→Rust.

**Migrated reads this slice (deliberately bounded):** the Logbook list (paginated,
with band/mode/callsign/date filters) and the total QSO count. Everything else —
stats aggregations, map snapshots, DXCC rollups, complex `#Predicate` fetches —
stays on SwiftData and migrates later as the Rust query/analytics surface grows.
The seam makes that additive, not a rewrite.

**Correctness obligation:** `FfiQso → QSOSnapshot` must produce the same snapshot
as the SwiftData path — identical field mapping and sort order (`fetch_qsos` must
match the Logbook's date-desc ordering). Enforced by `QSOParityProbe` in `shadow`.

## Flag & rollout states

- Hidden `ExperimentalFeature.rustStoreQSO` reveals controls in Settings → Data
  Migration (off by default; invisible to normal users).
- `@AppStorage("cwStoreQSOMode")` enum `off | shadow | on` is the rollout state,
  shown only when the experiment is enabled.

Fully reversible — SwiftData is always intact and never written by the Rust path:

| Mode | Mirror | Logbook reads | User-visible |
|------|--------|---------------|--------------|
| `off` | not observing | SwiftData | today's behavior |
| `shadow` | dual-writing | SwiftData (authoritative) + Rust compared | none |
| `on` | dual-writing | Rust | Rust serves list + count |

Flip to `off` = instant rollback.

## Verification — `QSOParityProbe`

In `shadow`, after each routed read, compare SwiftData vs Rust on: (a) count,
(b) ordered `id` list, (c) a field checksum of the page. Log the first-N divergent
ids + which field differs to the in-app diagnostics surface (same as the importer
verify). Plus a manual **"Run QSO parity check"** action doing a full paged sweep.

**Metadata pseudo-mode trap:** `WEATHER`/`SOLAR`/`NOTE` are stored as QSOs but
filtered out of the logbook via `QSOMode.isMetadata`. The Rust read path + snapshot
must apply the identical filter or parity shows false mismatches. The probe
compares like-for-like.

## Edge cases & risks

- **Read-after-write staleness in `on`.** Mirror upserts are async, so a save then
  immediate Logbook refresh could miss the latest row. The read path `await`s a
  `mirror.drain()` (pending-writes barrier) before a Rust read in `on` mode.
- **Deletes** — `willSave` id-capture map (above); covered by the new `delete_qso`.
- **Batch-import storms** — batched, off-main, serial.
- **Metadata pseudo-modes** — identical `isMetadata` filtering on both paths.
- **Concurrency** — `object: nil` observation catches all contexts; the serial
  actor orders writes.
- **Seed/mirror gap on enable** — start mirror before the idempotent reconcile.

## Testing

- **Rust:** `delete_qso` + `notify(.Delete)` tests.
- **Swift unit (in-memory):** save insert/update/delete → assert mirror produced
  matching Rust rows incl. deletion; `RustQSOReadSource` page/count matches
  SwiftData on a fixture; `QSOParityProbe` clean on identical data and catches an
  injected divergence; metadata-mode filtering parity.
- **Device:** enable `shadow` on the real store, run the parity sweep → expect zero
  mismatches; flip `on`, confirm Logbook + count identical; flip `off` → rollback.

## Scope

## Decomposition (revised during planning, 2026-06-14)

Planning revealed the Logbook list is far more coupled than the design assumed: it
holds `@Model QSO` objects (delete/select/group by `persistentModelID`) and filters
via the arbitrary `.cwquery` DSL (`ParsedQuery` → SwiftData `#Predicate` or an
in-memory `((QSO) -> Bool)` closure). The decision (2026-06-14) is to serve the
*full* list from Rust including DSL-filtered queries — which requires porting the
query compiler to SQLite. That is a separate subsystem. The cutover therefore
splits into three sequenced sub-projects, each with its own plan:

- **A — Cutover infrastructure + count (THIS plan). ✅ DONE 2026-06-14.**
  `CwStoreMirror`, shared `FieldStore` accessor, `QSOReadSource` seam, `QSOParityProbe`,
  flag/mode UI, `delete_qso`/`notify(.Delete)`. First routed read: the **total QSO
  count** (`qso_count()`). Ships and de-risks the pipeline independently.
- **B — `.cwquery` → Rust/SQLite query compiler + ServicePresence live mirror.
  ✅ DONE 2026-06-15** (commits `3e977f4b`..`e611e4c6`; see
  [B design](2026-06-15-qso-cutover-B-query-compiler-design.md),
  [B plan](2026-06-15-qso-cutover-B-query-compiler-plan.md),
  [B→C handoff](2026-06-16-qso-cutover-B-handoff.md)). Full-DSL AST→SQL compiler in
  `cw-store/query` at parity with the Swift `QueryCompiler`, proven by a 68-query
  Swift↔Rust corpus acceptance test. `service_presence` live-mirrored to back
  `synced:`/`pending:`. `RustQSOReadSource.page(query:)`/`count(query:)` →
  `QSORowSnapshot` is the seam C consumes.
- **C — `LogsListView` on snapshots + Rust list read. ✅ DONE 2026-06-16** (commit
  `3b8d2fa0`; see [C design](2026-06-16-qso-cutover-C-design.md),
  [C handoff](2026-06-16-qso-cutover-C-handoff.md)). The Logbook renders a
  backend-agnostic `QSORowSnapshot` from a `LogbookSnapshotSource` routed by
  `cwStoreQSOMode` (`off`/`shadow` → SwiftData, `on` → Rust). `QSORowSnapshot` widened
  (+ `[PresenceSummary]`); Rust `fetch_qsos_query` projects presence via a batched
  `WHERE qso_id IN (...)`. Writes + detail id-bridge to live `QSO` (`LogbookIDBridge`);
  `on` mode drains the mirror before re-paging. Presence parity proven in
  `QueryParityTests`.

**All three sub-projects (A, B, C) are complete.** Remaining cutover work (separate,
out of scope here):

- **Write-cutover W0 (DONE 2026-06-16):** `QSOWriteSink` seam + `CwStoreMirror`
  echo-suppression; hide/unhide write cw-store first in `on` mode, SwiftData kept as the
  CloudKit sync adapter. `QSOWriteSinkTests` green on device. See
  [W0 design](2026-06-16-qso-cutover-W0-write-seam-design.md) /
  [W0 plan](2026-06-16-qso-cutover-W0-write-seam-plan.md).
- **Write-cutover W1 (DONE 2026-06-16):** interactive writes — `logQSO` + `QSOEditSheet`
  edit routed cw-store-first via `QSOWriteSink.upsert`/`commitUpsert`; `setHidden`
  delegates to the shared upsert. The consumer-snapshot unwind (logQSO returning a
  snapshot) is deferred to the SwiftData-removal slice — not required for write authority.
  See [W1 design](2026-06-16-qso-cutover-W1-interactive-writes-design.md) /
  [W1 plan](2026-06-16-qso-cutover-W1-interactive-writes-plan.md).
- **Write-cutover W2 (DONE 2026-06-16):** bulk paths — bulk soft-delete,
  group-into-session, and the "Delete All Hidden" hard-delete routed cw-store-first via
  `QSOWriteSink.upsertBatch`/`deleteBatch`. ADIF/LoFi import are **deferred** (background
  `ModelContext`; `CwStoreMirror` already mirrors their saves into cw-store, so this is an
  authority-ordering gap, not a correctness gap — cw-store-first imports need a
  background-safe seam path). See
  [W2 design](2026-06-16-qso-cutover-W2-bulk-writes-design.md) /
  [W2 plan](2026-06-16-qso-cutover-W2-bulk-writes-plan.md).
- Non-QSO/ServicePresence entities; stats/map/aggregation reads; deleting SwiftData;
  macOS Sweep.

## Scope (sub-project A)

**In:** `CwStoreMirror` (QSO only), shared `FieldStore` accessor, `QSOReadSource`
seam, **total-count** read migration, `QSOParityProbe`, the flag + mode setting,
`delete_qso`/`notify(.Delete)` in `cw-ffi`.

**Out (deferred):** the Logbook list (sub-projects B + C); all other entities;
stats / map / aggregation reads; **cutting SwiftData writes** (Rust stays a mirror —
SwiftData remains system of record this slice); macOS Sweep (same pattern, later);
deleting SwiftData.

# SwiftData → SQLite (cw-store) Importer — Design

**Date:** 2026-06-14
**Status:** Implemented + verified on device (13,263 rows across 12 tables, verify clean) — see Progress
**Companion docs:** [rust-core migration](2026-06-13-rust-core-migration.md) · [handoff](2026-06-13-rust-core-handoff.md) · [fidelity audit](2026-06-14-cw-store-fidelity-audit.md)
**Phase:** 4 (the last piece before the entity-by-entity consumer cutover)

---

## Progress (2026-06-14)

Built and unit-tested end-to-end; wired to a manual Settings trigger and
deployed to device. Debugging an on-device crash on the user's real store.

**Done & committed:**
- **Schema fidelity:** audited all 12 entities; only QSO was a sketch. Expanded
  QSO to full fidelity (~48 fields); regenerated bindings. The other 11 already
  matched. ([fidelity audit](2026-06-14-cw-store-fidelity-audit.md))
- **Importer engine** (`swift/packages/CarrierWaveData/Sources/CarrierWaveData/Import/`):
  `SwiftDataStoreImporter` (batched read + faithful `project(_:)` for all 12
  entities + idempotent upsert), `verify(_:)`/`compareCounts(_:to:)` (no-rows-lost
  gate), `CwStoreImportCoordinator` (App Group store URL + device-local non-synced
  SQLCipher key + `UserDefaults` completion marker). 12 Import tests pass.
- **Trigger:** a "Migrate to Rust Store" row in Settings → Experiments
  (`ExperimentsView`), runs `runIfNeeded` and shows the outcome inline.
- **Key decision (cross-platform):** the SQLCipher at-rest key is per-device,
  generated locally, **never synced/shared across platforms** — each platform
  uses its native secure storage; cross-device convergence is the sync layer's
  job, not key sharing. (`KeychainHelper.Keys.cwStoreEncryptionKey`, device-local.)

**Resolved (2026-06-14) — two real root causes, neither of which was the context.**
The earlier context/`@ModelActor`/`sortBy` iterations were all dead ends; the
fetch site was never the problem.

1. **`WebSDRFavorite` fetch crash** — `SwiftData/ModelContext.swift:712: Failed to
   cast model WebSDRFavorite ... to WebSDRFavorite` (EXC_BREAKPOINT). Cause: the
   iOS schema was built as `CarrierWaveSchema.models + [...]` and the appended list
   re-added `WebSDRRecording` + `WebSDRFavorite`, which `CarrierWaveSchema.models`
   already contained. A model listed twice makes SwiftData build two dynamic
   subclasses; a bare `FetchDescriptor` materializes one and can't cast it to the
   other. Only entities with rows tripped it (zero recordings → empty fetch → no
   cast), which masqueraded as entity-specific. **Fix:** one deduplicated
   `AppSchema.models` (used by the app container *and* `TestModelContainer`) +
   `AppSchemaTests` uniqueness guard. (See [[swiftdata-gotchas]].)
2. **`activation_metadata` verify failure** — `src N ≠ stored M`. Cause: cw-store
   keyed the table on `park_reference` alone, but the entity's natural key is
   `(parkReference, date)` (one row per park per day; the app + cloud-sync layer
   look it up by park *and* date). Multi-day activations of the same park collapsed
   on upsert. **Fix:** composite PK `(park_reference, date)` in `cw-store` +
   `cw-ffi` (by-key fetch now takes `date`), schema **v3** migration rebuilds the
   table (seed-only, repopulated by the re-run import), regenerated bindings,
   regression test `same_park_different_dates_are_distinct_rows`.

**Verified on device:** `Imported 13263 rows across 12 tables`, verify clean,
completion marker set, no crash. The diagnostic win that unblocked it: surfacing
the SwiftData fatal-error message via an Xcode-attached run (the SIGTRAP hides it
from the `.ips`).

**Next:** the seed is done. The entity-by-entity consumer cutover (replacing
`@Query`/reads with the Rust store behind a flag) is the remaining Phase-4 epic.
Follow-ups noted in code: a dedicated (non-main-context) read path for very large
libraries; widget/watch shared-but-non-synced key access at cutover.

---

## Goal

Move every row of the user's existing SwiftData store into the new encrypted
Rust `cw-store` (SQLCipher), **once**, on a device, without data loss — so the
apps can begin reading from the Rust store behind a feature flag. This is the
one-time seed; ongoing writes are handled later by the consumer cutover.

Non-goal: changing any read path or deleting SwiftData. The importer only
*populates* the Rust store. The app keeps running on SwiftData until the
separate cutover work flips reads over.

## Locked decision (this review)

**Swift reads, calls the FFI upserts.** The importer is a Swift type in
`CarrierWaveData` that:

1. opens the existing `ModelContainer` (the user's real store),
2. batch-fetches each `@Model`,
3. projects each row into the matching `Ffi<Entity>` DTO,
4. calls the existing `FieldStore.upsert<Entity>(...)`.

Rejected alternative: Rust opens SwiftData's backing `.store` SQLite directly.
That couples Rust to SwiftData's *private, undocumented* schema (table names like
`ZQSO`, mangled column names, entity-version metadata) which Apple changes
between OS releases — brittle and untestable. The Swift pass reuses the typed
`@Model` layer and the FFI surface we already built (all 12 entities have
`upsert` + round-trip tests), so there is no new boundary code.

## Source entities (12)

All live in `CarrierWaveData/Sources/CarrierWaveData/Models/` (+ `Macros/`), and
each already has a 1:1 `Ffi<Entity>` DTO and `FieldStore.upsert*` on the Rust
side:

| SwiftData `@Model` | FFI DTO / upsert | Primary key |
|---|---|---|
| `QSO` | `FfiQso` / `upsertQso` | `id` (UUID string) |
| `LoggingSession` | `FfiLoggingSession` / `upsertLoggingSession` | `id` |
| `ServicePresence` | `FfiServicePresence` / `upsertServicePresence` | `id` |
| `SessionSpot` | `FfiSessionSpot` / `upsertSessionSpot` | `id` |
| `ActivationMetadata` | `FfiActivationMetadata` / `upsertActivationMetadata` | `parkReference` (natural) |
| `ActivityLog` | `FfiActivityLog` / `upsertActivityLog` | `id` |
| `EquipmentItem` | `FfiEquipmentItem` / `upsertEquipmentItem` | `id` |
| `RadioMacro` | `FfiRadioMacro` / `upsertRadioMacro` | `id` |
| `WebSDRRecording` | `FfiWebSDRRecording` / `upsertWebsdrRecording` | `id` |
| `WebSDRFavorite` | `FfiWebSDRFavorite` / `upsertWebsdrFavorite` | `hostPort` (natural) |
| `UploadDestination` | `FfiUploadDestination` / `upsertUploadDestination` | (composite) |
| `CloudSyncMetadata` | `FfiCloudSyncMetadata` / `upsertCloudSyncMetadata` | `(entityType, localId)` (composite) |

The projection (`@Model` → `Ffi*`) is the bulk of the mechanical work. Each is a
plain field copy; the FFI DTO field names/types are already fixed by the Rust
side. Metadata pseudo-modes (`WEATHER`/`SOLAR`/`NOTE`) are stored as QSOs in
SwiftData today — they import as-is (the store is a faithful mirror; filtering
stays a read-layer concern per the existing `QSOMode.isMetadata` rule).

**`CloudSyncMetadata` is imported verbatim** like every other table (decided
2026-06-14) — preserving the existing record-name↔local-id mappings and dirty
flags so sync can resume post-cutover without a full re-reconcile. (Risk to watch
in the cutover: tokens that don't match the new store's identity; the importer
just copies, it doesn't validate them.)

## Idempotency & re-runnability

The import must be safe to run twice (interrupted launch, retry after a crash).
Every Rust `upsert` is `INSERT … ON CONFLICT(pk) DO UPDATE`, so re-running
overwrites rather than duplicating — **provided the primary key is stable**. The
three natural/composite keys above are the ones to watch: confirm the SwiftData
value that feeds each PK is the same one `cw-store` keys on (e.g.
`ActivationMetadata.parkReference`, `WebSDRFavorite.hostPort`). A unit test per
natural-key entity asserts re-import is a no-op on count.

## Store location & encryption key

- **New store path:** a fresh `cw-store.db` in the **shared App Group container**
  (decided 2026-06-14), *separate* from the SwiftData `.store` so the source is
  never mutated and a failed import is just a file delete + retry. The App Group
  lets the iOS app, widgets, and watch all open the same local file (SQLCipher
  tolerates multiple readers). Note: an App Group shares files only *within one
  Apple device's* process family — iOS↔macOS↔Android convergence is the sync
  layer's job (Phase 5), where each device keeps its own local store. The
  importer only seeds the local store on the device it runs on.
- **SQLCipher key:** generated on first import, stored in the Keychain (Rust
  never owns it — `FieldStore.open(path:key:)` takes it). Reuse the existing
  keychain-helper pattern from `CarrierWaveData` (credentials already live
  there). **Open question:** key-recovery flow if the keychain item is lost on a
  device restore (tracked in the handoff's open-questions table) — for the
  *importer* we can regenerate + re-import from the still-present SwiftData store,
  so loss is recoverable as long as SwiftData hasn't been deleted.

## Trigger & lifecycle

- Runs **once**, gated behind an off-by-default experimental flag
  (`ExperimentalFeature`, hidden) so it never touches a normal user's device
  until we opt them in. Mirrors the iCloud-sync experiment's caution.
- A `UserDefaults` marker (`cwStoreImportCompletedVersion`) records success so we
  don't re-scan on every launch; a mismatch (or absent marker) triggers a run.
- Executed off the main thread on a background actor — see Performance.
- Reuses the **emergency-backup** posture already in `ContainerSetup`: before the
  first import, snapshot is unnecessary (we don't modify SwiftData), but we log
  start/finish + per-table counts to the in-app log surface (never `os_log`).

## Dry-run / verify mode

A `--verify` (debug-menu) mode that imports into a throwaway in-memory Rust store
(`FieldStore.openInMemory`) and reports, per table:

- SwiftData row count vs Rust row count after import (must match),
- a cheap content checksum (e.g. XOR/FNV of sorted `id`s, or sum of a numeric
  column) to catch silent field-mapping drops,
- the first N mismatching keys if counts differ.

The report renders in an in-app diagnostics view and is copyable into a bug
report. This is the gate we trust before enabling the real import for anyone.

## Performance (MANDATORY — see swift/docs/PERFORMANCE.md)

- **Batched fetch, `fetchLimit` always set, fresh `ModelContext` per batch.** No
  unbounded `FetchDescriptor`. Reuse `BatchedFetch` (already in
  `CarrierWaveData/Utilities/`).
- **≤ 1,000 objects in memory at a time.** Page through QSO/ServicePresence (the
  large tables) in 1,000-row batches, converting each batch to `Ffi*` value
  types and upserting before fetching the next.
- **One background actor; scans serialized.** Import each table sequentially, not
  concurrently — concurrent full-table scans multiply peak memory and OOM 4 GB
  devices.
- Main-thread impact must be O(1) (a progress counter); all fetch + upsert work
  is off-main.

## Failure handling

- The new store is a separate file → any failure is recoverable by deleting it
  and re-running; SwiftData (the source of truth) is untouched.
- Per-batch upserts run inside the Rust store's single-writer mutex; a mid-import
  crash leaves a partial store, which the idempotent re-run completes.
- The completion marker is written **only** after the verify counts match, so a
  partial import never looks "done."

## Test plan

- **Rust:** already covered — every entity has round-trip upsert/fetch tests.
- **Swift (CarrierWaveData tests, in-memory):**
  - Seed an in-memory `ModelContainer` with a few rows per `@Model`, run the
    importer into `FieldStore.openInMemory`, assert per-table counts + a sample
    row's fields survive the projection.
  - Re-run the import; assert counts unchanged (idempotency), especially the
    three natural/composite-key entities.
  - Verify-mode report matches on a known fixture; intentionally drop a field in
    a projection and assert the checksum catches it.
- **Device:** run `--verify` against a realistic log (10k+ QSOs) and confirm the
  report is clean and the run stays off the main thread (no hangs).

## Resolved (2026-06-14 review)

- **Store location:** shared App Group container (above).
- **CloudSyncMetadata:** imported verbatim (above).

## Open questions (resolve in code during implementation — not blocking)

1. Exact App Group identifier + the `cw-store.db` path within it (confirm the
   group is provisioned for the iOS app, widget, and watch targets).
2. `UploadDestination` / `CloudSyncMetadata` composite-key construction — read the
   `cw-store` schema to confirm the Swift-side value that maps onto the Rust PK so
   re-import is a no-op. (Code lookup, not a product decision.)

## Out of scope (later, separate work)

- Reading from the Rust store / replacing `@Query` (the consumer cutover).
- Deleting SwiftData (`import SwiftData` → 0).
- macOS Sweep lockstep wiring (same importer, but its own trigger).
- Entity deletes over the FFI (so `notify` can emit `Delete`).

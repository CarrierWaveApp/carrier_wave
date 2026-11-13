# Investigation: 1.94.0 launch crash loop — SwiftData→cw-store import watchdog kills

**Date:** 2026-07-02
**Status:** Resolved
**Outcome:** Seed import wrote one SQLite transaction (2 fullfsync barriers) per row on the main thread; batched into one off-main transaction per 500-row page.

## Problem Statement

Five `CarrierWave-2026-07-02-*.ips` crash reports from a device running 1.94.0
(build 17), iOS 26.5, between 10:35 and 10:44 local — the first launches after
updating to 1.94.0. The app appeared to crash on every launch.

## Crash Report Analysis

All five are `EXC_CRASH SIGKILL` with termination code `0x8BADF00D` (watchdog),
not code crashes:

| Time | Watchdog event | Frame 0 |
|------|----------------|---------|
| 10:35:20 | scene-update (10 s, background) | `sqlite3VdbeFreeCursorNN` |
| 10:35:40 | process-exit ("failed to terminate gracefully after 5.0s") | `__fcntl` (F_FULLFSYNC) |
| 10:41:21 | process-exit | `pwrite` |
| 10:42:41 | process-exit | `__fcntl` |
| 10:44:11 | scene-update | `__fcntl` |

Symbolicated with `atos` against the 2026-07-01 21:24 archive dSYM
(UUID `1C38EA93-C6C3-3D4F-91D8-AED65C381A59`). Every stack is identical below
the syscall:

```
CarrierWaveApp.applyQSOMirrorMode          CarrierWaveApp+QSOMirror.swift:43
→ CwStoreImportCoordinator.runIfNeeded     CwStoreImportCoordinator.swift:90
→ SwiftDataStoreImporter.importAll         SwiftDataStoreImporter.swift:74/80
→ FieldStore.upsertQso / upsertServicePresence   (sync uniffi call, main thread)
→ rusqlite Connection::execute → sqlite3_step → vdbeCommit → unixSync/unixWrite
```

## Root Cause

Three compounding factors:

1. **The import runs at launch on the main actor.** Phase 1c made
   `CwStoreQSOMode` default `.on`, so `applyQSOMirrorMode` (called from the
   root `.task {}`) invokes `CwStoreImportCoordinator.runIfNeeded` on every
   launch. The importer is `@MainActor` by necessity (secondary `ModelContext`
   crashes in SwiftData's fetch for some entities on this store), and its
   `Task.yield()` only ran *between* 500-row batches.

2. **One transaction per row.** Each `FieldStore.upsert*` is a bare
   `Connection::execute` — an autocommit transaction. cw-store deliberately
   runs `synchronous=FULL` + `fullfsync=ON` + rollback journal for power-loss
   durability, so every commit costs two F_FULLFSYNC disk barriers. At
   ~10–30 ms per row, a 100k-QSO log needs tens of minutes of main-thread I/O.

3. **Version-keyed completion marker.** `runIfNeeded` compares the stored
   marker against the *current* app version, so the 1.94.0 update invalidated
   the 1.93.x marker and triggered a full re-seed. The marker is only written
   after import + verify complete, so each watchdog kill restarted the import
   from row zero on relaunch — a crash loop that can never converge on a large
   log. (Also why the crashes alternate between `scene-update` — user
   backgrounded the frozen app — and `failed to terminate gracefully` — user
   killed it / iOS asked it to exit and the main thread couldn't respond.)

The doc comments hid all this: the coordinator claimed "Triggered manually from
Settings (no launch-time work)" and "runs on the importer's `@ModelActor`
executor (off-main)" — both stale.

## Resolution

- **cw-store:** new `Store::in_transaction` helper (`unchecked_transaction`,
  commit on success, rollback on error) + tests.
- **cw-ffi:** batch upsert exports for all 12 imported entities
  (`upsert_qsos`, `upsert_service_presences`, …,
  `upsert_activation_metadata_batch`, `upsert_cloud_sync_metadata_batch`):
  whole batch in one transaction, one observer notify, empty batch is a no-op.
- **Swift:** `SwiftDataStoreImporter.batchedImport` now runs each batch
  entirely off-main in `Task.detached`: fresh `ModelContext(container)` with
  `autosaveEnabled = false` (PERFORMANCE.md batching pattern — the fresh
  context releases SwiftData's row cache between batches, so peak memory is
  ~one batch instead of the whole 100k-row table), project to `Sendable`
  `Ffi*` values, one-transaction batch write. Main-actor work per batch is
  O(1) bookkeeping. The old "must read on the main context" constraint was a
  misdiagnosis — the on-device fetch crash was a duplicated model in the
  schema, fixed by the `AppSchema.models` dedup (see
  docs/plans/2026-06-14-swiftdata-import-design.md); the mirror and reconciler
  already use background contexts on this store.
- Stale doc comments corrected; CHANGELOG entry under `[Unreleased]`.

Left as-is (deliberate): the version-keyed re-seed per app update (it heals
projection drift; now cheap enough) and the durability pragmas (power-loss
guarantee, see `apply_durability_pragmas`).

## Lessons Learned

- A "yields between batches" loop is still a watchdog risk if a single batch
  contains hundreds of synchronous fsyncs. Budget main-thread work per
  *suspension point*, not per loop iteration.
- Per-row autocommit against a `synchronous=FULL` + `fullfsync` store is ~2
  disk barriers per row. Any bulk write path against cw-store must batch into
  explicit transactions (`upsert_pota_parks` already did this; the importer
  did not).
- Watchdog `.ips` files with `WatchdogCPUStatistics` showing ~2–4% app CPU
  mean the main thread is *waiting* (I/O or lock), not spinning — look for
  syscall frames, not hot loops.
- Doc comments that describe threading/trigger behavior rot fast; when a call
  site moves (Settings → launch path), re-audit the callee's assumptions.

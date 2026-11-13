# LoggingSession write cutover — consumer-snapshot unwind spec

**Date:** 2026-06-20
**Branch context:** follows `rust/equipment-item-read-cutover` (read sources for all
entities + generic `EntityWriteSink` + routing for EquipmentItem / ActivityLog /
RadioMacro).
**Status:** mechanism + lifecycle saves + the POTA-split / midnight-rollover
co-mutating saves IMPLEMENTED (2026-06-20). `SeamWriteBatch` built and wired; routed:
the two multi-entity session deletes; the single-entity session lifecycle saves
(`EntityWriteSink<LoggingSession>`); and the QSO-co-mutating `endSession` /
`UTCDayBoundary` saves (`splitPOTAAtUTCMidnight` now returns a `SessionSplitChanges`,
committed via `commitSessionSplit` → `SeamWriteBatch`). Still deferred: `mergeSessions` /
`deleteSessionShell`, `+Continuity`, and off-main entity writes. `xc build` green.
**Trusting `on` mode still needs the device/CI write-sink test loop + on-device parity
sweep (below) — not run.**
**Companion:** [Rust-ification finish handoff](2026-06-18-rustification-finish-handoff.md)

---

## TL;DR

LoggingSession (and the other off-main / hot-path entities) **cannot** be routed
through the per-entity `EntityWriteSink` the way EquipmentItem/ActivityLog/RadioMacro
were, because their `modelContext.save()` calls are **shared, multi-entity
transactions** and the mirror's seam suppression is **global per save**. Routing a
shared save through a single-entity sink silently drops the co-mutated entities from
cw-store in `on` mode. The fix is a **coordinated multi-entity seam write** plus a
per-save-site mutation audit. This is the "consumer-snapshot unwind" the migration
plan defers; it is a hot-path refactor, not a mechanical find-replace.

## The mechanism that makes it unsafe

`CwStoreMirror` suppresses mirroring with a single global counter
(`CwStoreMirror.swift`):

```
func beginSeamWrite() { seamWriteDepth += 1 }
func endSeamWrite()   { seamWriteDepth = max(0, seamWriteDepth - 1) }
// on save notification:
if seamWriteDepth > 0 { return }   // skip ALL mirroring for this save
```

So `EntityWriteSink.upsert/delete` (which wraps `context.save()` in
`beginSeamWrite()/endSeamWrite()`) suppresses mirroring for the **entire** save —
every entity flushed by that `save()`, not just the routed one.

- **Why the 3 done entities were safe:** each write is *colocated* (mutate → save in
  the same function) and *single-entity* (the save flushes only that model). Suppress
  + canonical-write is exactly correct.
- **Why LoggingSession is not:** its saves are *separated* from the mutations and
  *shared*. `endSession`'s `save()` also flushes co-mutated QSO / ServicePresence /
  SessionSpot rows. Routing it through the session sink suppresses the mirror, so
  those co-mutated rows never reach cw-store → silent divergence (caught only by the
  parity sweep, and untestable in the package loop).

## Required mechanism: coordinated seam write

Add a batch seam that writes **all** co-mutated entities to cw-store under one
suppression window, then one save:

```swift
@MainActor
struct SeamWriteBatch {
    let store: FieldStore
    let mirror: CwStoreMirror?
    private var ops: [(FieldStore) throws -> Void] = []

    mutating func upsert<M: PersistentModel>(_ m: M) { ops.append(registry-resolved upsert for M) }
    mutating func delete<M: PersistentModel>(_ m: M) { ops.append(registry-resolved delete for M) }

    func commit(in context: ModelContext) throws {
        if mode == .on {
            for op in ops { try op(store) }   // cw-store first, ALL entities
            mirror?.beginSeamWrite(); defer { mirror?.endSeamWrite() }
            try context.save()                // one suppressed save
        } else {
            try context.save()
        }
    }
}
```

Resolve each op via the existing type-keyed `EntityWriteSinkRegistry` so the per-entity
`upsert_*`/`delete_*` FFI stays the single source of truth. A save site then becomes:
collect every model it mutates/deletes (session + QSOs + presence + spots) into one
`SeamWriteBatch`, `commit()` once.

## Methodology (per save site)

1. Read the whole enclosing function. Enumerate **every** model the `save()` flushes —
   not just the session: QSO inserts/edits, ServicePresence flips, SessionSpot
   deletes, ActivationMetadata, etc. SwiftData saves the whole dirty graph, so
   "what changed since the last save" is the real set.
2. If single-entity → route via `EntityWriteSink.commit*` (the done pattern).
3. If multi-entity → route via `SeamWriteBatch` with every co-mutated model.
4. If the mutation and the save are in different functions (create → `activateSession`),
   move the routing to the **save** site, and make sure the session object is in the
   batch there.
5. Leave un-auditable / background-actor saves un-routed — the mirror covers them as a
   follower. Do **not** half-route a shared save.

## Save-site inventory (to audit)

`LoggingSessionManager` is `@MainActor final class`; all `+` extensions inherit it, so
isolation is fine — the risk is co-mutation, not threading.

| File | Lines | Note |
|------|-------|------|
| `LoggingSessionManager.swift` | 198 (insert), 249, 304, 345 | create inserts session; save is in `activateSession` |
| `+SessionManagement.swift` | 58, 129, 167, 204, 281, 323, 338, 407, 440, 446, 488; deletes at 259/445/487 | endSession/pause/resume/delete — **shared saves** (delete session co-deletes SessionSpots at ~251) |
| `+SessionActivity.swift` | insert 42 | confirm entity type |
| `+Continuity.swift` | insert 110 | session auto-continuation (lifecycle) |
| `+UTCDayBoundary.swift` | insert 64 | midnight auto-rollover (lifecycle) |
| `+POTASplit.swift` | insert 93 | rove split (co-mutates QSOs) |
| `POTASplitRepairService.swift` | insert 83 | confirm isolation (Service, may be off-main) |
| `Views/Logs/LogsListView+GroupSession.swift` | insert 165 | group-into-session (co-mutates QSOs — already partly QSOWriteSink) |
| `Views/Sessions/SessionsView+Actions.swift` | delete 326 | session delete from UI |

`logQSO` (`ActivityLogManager.swift:270`, `LoggingSessionManager+QSOManagement.swift:108`)
is the QSO hot path — it co-mutates session.qsoCount + presence; it belongs to the QSO
write cutover, sequence together.

## Same pattern blocks the other deferred entities

- **SessionSpot** — ingested from the off-main spot pipeline; needs main-actor hop or an
  off-main seam variant.
- **WebSDRRecording** — written from background recording session; same.
- **ActivationMetadata** — written alongside session lifecycle; shared saves.
- **CloudSyncMetadata** — written by the CloudKit sync engine, not user CRUD; route in
  the sync layer, not a UI sink.
- **standalone ServicePresence** — the `markPresent`/`markUploaded` paths in
  `QSOProcessingActor` (off-main); `ServicePresenceWriteSink` exists but its call sites
  are unrouted for the same reason.
- **WebSDRFavorite** — ~~separate blocker~~ **RESOLVED 2026-06-20:** the app-target
  duplicate `@Model` was deleted; the favorites UI now resolves to the
  schema-registered `CarrierWaveData.WebSDRFavorite`. Favorite cutover unblocked.

## Acceptance

- Per entity: app-target `*WriteSink`/`SeamWriteBatch` tests (the `QSOWriteSinkTests`
  shape) green on a device/CI runner — **not** runnable in the package loop.
- On-device `shadow`-mode `QSOParityProbe`-style sweep shows zero divergence for the
  entity across a full session lifecycle (create → log QSOs → mark uploads → end →
  delete).
- `cargo test --workspace` + `swift test --filter RustStore` stay green (no Rust change
  expected).

## Why not just leave it to the mirror

The mirror already keeps cw-store in sync as a *follower*, so `on`-mode **reads** are
correct today (the read sources landed). The write cutover only changes follower →
canonical, which is what lets the SwiftData replica eventually be removed (Phase 4 exit
criterion). Until then, deferring is safe; half-routing a shared save is not.

# QSO Rust-Store Cutover — W2: Bulk QSO Writes — Design

**Date:** 2026-06-16
**Status:** Draft (executing autonomously per user direction; no approval gate)
**Phase:** 4 (consumer cutover — write side, bulk writes)
**Companion docs:** [W0 design](2026-06-16-qso-cutover-W0-write-seam-design.md) · [W1 design](2026-06-16-qso-cutover-W1-interactive-writes-design.md) · [cutover design](2026-06-14-qso-rust-store-cutover-design.md)

---

## Goal

Extend the `QSOWriteSink` seam with **batch** upsert/delete and route the main-actor bulk
QSO write paths through it so they are cw-store-first/canonical in `on` mode, consistent
with the interactive writes (W0/W1). Behind the same `cwStoreQSOMode` experiment.

## What's in scope (main-actor, bounded)

1. **Bulk soft-delete** — `LogsListContentView.softDeleteQSOs` sets `isHidden = true` (and
   clears `needsUpload`) on the selected QSOs, then one `try? modelContext.save()`.
2. **Group-into-session** — `createSessionFromSelection` inserts a new `LoggingSession` and
   re-points the targeted QSOs' `loggingSessionId`, then one save. (Only the QSO upserts
   route through the seam; the `LoggingSession` insert rides the same `context.save()` —
   the `LoggingSession` *entity* cutover is separate, out of scope.)
3. **"Delete All Hidden" hard-delete** — `AllHiddenQSOsView` batch-fetches hidden QSOs and
   `modelContext.delete`s them in a loop, then saves. The only true hard-delete path.

All three currently do a single batched `try? modelContext.save()` that bypasses the seam;
in `on` mode `CwStoreMirror` mirrors that save into cw-store **asynchronously, SwiftData-
first**. W2 makes them cw-store-first/canonical, matching W0/W1.

## What's deferred (and why)

**ADIF import + LoFi sync import are NOT routed through the seam in W2.** They run on
**background `ModelContext`s** (the PERFORMANCE.md batching pattern) and insert thousands of
rows. The `QSOWriteSink` seam is `@MainActor`, so a cw-store-first batch path for imports
would need a background-safe seam variant. Crucially, this is **not a correctness gap**:
`CwStoreMirror` is explicitly built to observe background-context saves (its
`testBackgroundContextSaveMirrorsWithoutAssumingMainActor` proves it) and already mirrors
every import batch into cw-store. So imports remain SwiftData-first + mirror-followed; only
the "cw-store-first authority" for imports is deferred — to a future slice that either adds
a background-safe seam or is folded into the SwiftData-removal work. This is documented as a
known seam, not silently skipped.

## Design

### Batch methods on `QSOWriteSink`

```swift
    /// Commit a batch of QSO inserts/updates (the caller has already inserted/mutated
    /// them in `context`). `on`: upsert every QSO + its ServicePresence to cw-store
    /// FIRST, then one mirror-suppressed save. Other modes: one plain save.
    func upsertBatch(_ qsos: [QSO], in context: ModelContext) throws {
        if modeProvider() == .on {
            for qso in qsos {
                try writeUpsertToStore(qso)   // reuses the W1 helper
            }
            mirror?.beginSeamWrite()
            defer { mirror?.endSeamWrite() }
            try context.save()
        } else {
            try context.save()
        }
    }

    /// Commit a batch of QSO hard-deletes. `on`: delete every QSO (and its
    /// ServicePresence rows) from cw-store FIRST, then `context.delete` each + one
    /// mirror-suppressed save. Other modes: `context.delete` each + one plain save.
    func deleteBatch(_ qsos: [QSO], in context: ModelContext) throws {
        if modeProvider() == .on {
            for qso in qsos {
                for presence in qso.servicePresence {
                    try store.deleteServicePresence(id: SwiftDataStoreImporter.uuid(presence.id))
                }
                try store.deleteQso(id: SwiftDataStoreImporter.uuid(qso.id))
            }
            for qso in qsos {
                context.delete(qso)
            }
            mirror?.beginSeamWrite()
            defer { mirror?.endSeamWrite() }
            try context.save()
        } else {
            for qso in qsos {
                context.delete(qso)
            }
            try context.save()
        }
    }
```

(The cw-store deletes happen while the QSOs are still alive, so `qso.servicePresence` and
`qso.id` are readable; `context.delete` is applied after, then the single save.)

### Static routing helpers (mirror the W1 `commitUpsert`)

```swift
    @MainActor
    static func commitUpsertBatch(_ qsos: [QSO], in context: ModelContext) throws {
        if let sink = QSOWriteSinkRegistry.current {
            try sink.upsertBatch(qsos, in: context)
        } else {
            try context.save()
        }
    }

    @MainActor
    static func commitDeleteBatch(_ qsos: [QSO], in context: ModelContext) throws {
        if let sink = QSOWriteSinkRegistry.current {
            try sink.deleteBatch(qsos, in: context)
        } else {
            for qso in qsos { context.delete(qso) }
            try context.save()
        }
    }
```

### Route the three sites

- **`softDeleteQSOs`**: after the `for qso in toDelete { qso.isHidden = true; … }` mutation
  loop, replace `try? modelContext.save()` with
  `do { try QSOWriteSink.commitUpsertBatch(toDelete, in: modelContext) } catch { modelContext.rollback(); CwStoreWriteLog.shared.record("Bulk hide failed: \(error.localizedDescription)"); return }`.
- **`createSessionFromSelection`**: after inserting the session and re-pointing
  `targeted` QSOs, replace `try? modelContext.save()` with
  `commitUpsertBatch(targeted, in:)` in the same do/catch/rollback shape. The session
  insert is committed by that same save.
- **`AllHiddenQSOsView` delete loop**: replace the per-batch `for qso in batch { modelContext.delete(qso) }` + `try? modelContext.save()` with
  `do { try QSOWriteSink.commitDeleteBatch(batch, in: modelContext) } catch { modelContext.rollback(); CwStoreWriteLog.shared.record("Delete hidden failed: \(error.localizedDescription)"); break }`.

### Failure / divergence

Same risk class as W0/W1: on a cw-store-write failure the caller `rollback()`s SwiftData and
logs. For `deleteBatch`, a failure after some cw-store deletes but before the SwiftData save
leaves cw-store missing rows SwiftData still has — a rare divergence (disk-full/corruption
class) logged to the Data Migration diagnostics and caught by the parity sweep. Acceptable
behind an off-by-default experiment.

## Testing

- Extend `QSOWriteSinkTests`: `upsertBatch` of two new QSOs in `on` mode lands both in the
  cw-store base set (suppressed, no duplicates); `deleteBatch` of two QSOs removes them from
  cw-store and SwiftData. Existing W0/W1 tests must still pass.
- Device (now that `theseus` is unlocked): bulk-hide several QSOs (leave the Logbook),
  group some into a session, "Delete All Hidden" — parity check clean throughout.

## Scope

**In:** `QSOWriteSink.upsertBatch`/`deleteBatch` + `commitUpsertBatch`/`commitDeleteBatch`;
route `softDeleteQSOs`, `createSessionFromSelection`, `AllHiddenQSOsView` delete; tests;
changelog/doc.

**Out (documented):** ADIF/LoFi import cw-store-first (background-context; mirror already
covers correctness); `LoggingSession`/other entity cutover; consumer-snapshot unwind;
deleting SwiftData; macOS Sweep.

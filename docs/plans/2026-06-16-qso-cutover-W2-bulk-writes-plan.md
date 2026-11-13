# QSO Write Cutover W2 (Bulk Writes) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`).

**Goal:** Add batch upsert/delete to `QSOWriteSink` and route the three main-actor bulk QSO write paths (bulk soft-delete, group-into-session, "Delete All Hidden") through it; defer imports.

**Spec:** [W2 design](2026-06-16-qso-cutover-W2-bulk-writes-design.md)

**Build/test:** `xc build` / `xc test-unit` (device `theseus` is unlocked). If the `xc` wrapper exits non-zero with empty output, confirm via underlying `xcodebuild` and say so. Hooks run on edit.

---

## Task 1: Batch seam methods + tests

**Files:** Modify `swift/ios/CarrierWave/Services/RustStore/QSOWriteSink.swift`; Test `swift/ios/CarrierWaveTests/RustStore/QSOWriteSinkTests.swift`

- [ ] **Step 1: Append tests** to `QSOWriteSinkTests`:

```swift
    /// `on` mode: upsertBatch writes both new QSOs to the cw-store base set, suppressed.
    func testOnModeUpsertBatchWritesAll() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let store = try FieldStore.openInMemory(key: "on-upsert-batch")
        let mirror = CwStoreMirror(store: store)
        mirror.start()
        defer { mirror.stop() }

        let qsos = QSOFactory.generate(count: 2)
        for qso in qsos { context.insert(qso) }
        let sink = QSOWriteSink(store: store, mirror: mirror, modeProvider: { .on })
        try sink.upsertBatch(qsos, in: context)
        await mirror.drain()

        XCTAssertEqual(try Int(store.qsoCountQuery(query: "")), 2)
        XCTAssertEqual(try store.qsoCount(), 2, "no duplicates from an echo")
    }

    /// `on` mode: deleteBatch removes the QSOs from cw-store and SwiftData.
    func testOnModeDeleteBatchRemovesAll() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let store = try FieldStore.openInMemory(key: "on-delete-batch")
        let mirror = CwStoreMirror(store: store)
        mirror.start()
        defer { mirror.stop() }

        let qsos = QSOFactory.generate(count: 2)
        for qso in qsos { context.insert(qso) }
        let sink = QSOWriteSink(store: store, mirror: mirror, modeProvider: { .on })
        try sink.upsertBatch(qsos, in: context)
        XCTAssertEqual(try store.qsoCount(), 2)

        try sink.deleteBatch(qsos, in: context)
        await mirror.drain()
        XCTAssertEqual(try store.qsoCount(), 0, "deleted from cw-store")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<QSO>()), 0, "deleted from SwiftData")
    }
```

- [ ] **Step 2: Run; verify FAIL to compile** (batch methods absent).

- [ ] **Step 3: Implement.** Add to the `QSOWriteSink` struct (after `upsert`):

```swift
    /// Commit a batch of QSO inserts/updates. `on`: upsert every QSO + its
    /// ServicePresence to cw-store FIRST, then one mirror-suppressed save. Other modes:
    /// one plain save. Throws on a canonical-write failure — the caller must rollback.
    func upsertBatch(_ qsos: [QSO], in context: ModelContext) throws {
        if modeProvider() == .on {
            for qso in qsos {
                try writeUpsertToStore(qso)
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

And add to the routing extension (next to `commitUpsert`):

```swift
    /// Batch upsert through the active seam, or a plain save when no seam is active.
    @MainActor
    static func commitUpsertBatch(_ qsos: [QSO], in context: ModelContext) throws {
        if let sink = QSOWriteSinkRegistry.current {
            try sink.upsertBatch(qsos, in: context)
        } else {
            try context.save()
        }
    }

    /// Batch hard-delete through the active seam, or a plain SwiftData delete+save.
    @MainActor
    static func commitDeleteBatch(_ qsos: [QSO], in context: ModelContext) throws {
        if let sink = QSOWriteSinkRegistry.current {
            try sink.deleteBatch(qsos, in: context)
        } else {
            for qso in qsos {
                context.delete(qso)
            }
            try context.save()
        }
    }
```

`writeUpsertToStore` (private, from W1) is reused — do not duplicate it.

- [ ] **Step 4:** Run `QSOWriteSinkTests` — the 2 new + all existing W0/W1 tests pass.
- [ ] **Step 5: Commit** — `git commit -m "Phase 4 (W2): QSOWriteSink batch upsert/delete + routing"`.

---

## Task 2: Route bulk soft-delete + group-into-session

**Files:** Modify `swift/ios/CarrierWave/Views/Logs/LogsListView+BulkDelete.swift`, `swift/ios/CarrierWave/Views/Logs/LogsListView+GroupSession.swift`

- [ ] **Step 1: `softDeleteQSOs`** (BulkDelete.swift) — replace the `try? modelContext.save()` (right after the `for qso in toDelete { … }` mutation loop, before the `.didLogQSO` post) with:

```swift
        do {
            try QSOWriteSink.commitUpsertBatch(toDelete, in: modelContext)
        } catch {
            modelContext.rollback()
            CwStoreWriteLog.shared.record("Bulk hide failed: \(error.localizedDescription)")
            return
        }
```

Leave the optimistic `snapshots.removeAll { … }` and the trailing `NotificationCenter.default.post(name: .didLogQSO, …)` unchanged (the post stays after the do/catch).

- [ ] **Step 2: `createSessionFromSelection`** (GroupSession.swift) — replace the `try? modelContext.save()` (after the `for qso in targeted { qso.loggingSessionId = sessionId; … }` loop) with:

```swift
        do {
            try QSOWriteSink.commitUpsertBatch(targeted, in: modelContext)
        } catch {
            modelContext.rollback()
            CwStoreWriteLog.shared.record("Group into session failed: \(error.localizedDescription)")
            return
        }
```

Leave `selectedQSOIDs.removeAll()`, `isSelectMode = false`, and the `.didLogQSO` post after the do/catch unchanged. (The new `LoggingSession` was inserted before this; it is committed by the same save inside `commitUpsertBatch`.)

- [ ] **Step 3:** `xc build` → BUILD OK.
- [ ] **Step 4: Commit** — `git commit -m "Phase 4 (W2): route bulk soft-delete + group-into-session through seam"`.

---

## Task 3: Route "Delete All Hidden" hard-delete

**Files:** Modify `swift/ios/CarrierWave/Views/Settings/AllHiddenQSOsView.swift`

- [ ] **Step 1:** In the delete-all loop (currently `for qso in batch { modelContext.delete(qso) }` followed later by `try? modelContext.save()`), replace the per-batch delete+save so the batch is routed through the seam. Read the surrounding `while`/batch loop first. The current shape is:

```swift
            for qso in batch {
                modelContext.delete(qso)
            }
            await Task.yield()
        }
        try? modelContext.save()
        await loadHiddenQSOs()
```

Change it to delete each fetched `batch` through the seam inside the loop, and drop the trailing single save (each batch now commits itself):

```swift
            do {
                try QSOWriteSink.commitDeleteBatch(batch, in: modelContext)
            } catch {
                modelContext.rollback()
                CwStoreWriteLog.shared.record("Delete hidden failed: \(error.localizedDescription)")
                break
            }
            await Task.yield()
        }
        await loadHiddenQSOs()
```

(That is: replace the `for qso in batch { modelContext.delete(qso) }` block with the `do/catch` calling `commitDeleteBatch(batch, …)`, and remove the now-redundant `try? modelContext.save()` after the `while` loop. Verify the exact loop shape by reading the file before editing; if it differs materially, report NEEDS_CONTEXT.)

- [ ] **Step 2:** `xc build` → BUILD OK.
- [ ] **Step 3: Commit** — `git commit -m "Phase 4 (W2): route Delete All Hidden through seam"`.

---

## Task 4: Changelog + cutover-doc note

- [ ] **Step 1: CHANGELOG.md** — under the existing `[Unreleased] → ### Changed` (append a bullet; do NOT create a second `### Changed`):

```markdown
- **iOS Field — QSO Rust Store write-cutover W2 (bulk writes), hidden experiment.** Bulk hide, group-into-session, and "Delete All Hidden" now write the Rust cw-store first/canonically in `on` mode via `QSOWriteSink` batch upsert/delete. ADIF/LoFi import stay mirror-followed for now (background-context; cw-store-first deferred). `off`/`shadow` unchanged.
```

- [ ] **Step 2: cutover doc** (`docs/plans/2026-06-14-qso-rust-store-cutover-design.md`) — change the "Write-cutover W2 (in progress)" line to DONE with a pointer to the W2 design/plan and the import-deferral note.

- [ ] **Step 3: Commit** — `git commit -m "Phase 4 (W2): changelog + cutover-doc note"`.

---

## Self-Review

- Batch upsert/delete + routing helpers, reusing `writeUpsertToStore` → Task 1; tests cover batch upsert + delete. ✓
- Three main-actor bulk sites routed with rollback+log → Tasks 2-3. ✓
- Imports deferred, documented (not silently skipped) → design doc + changelog. ✓
- Type consistency: `upsertBatch`/`deleteBatch`/`commitUpsertBatch`/`commitDeleteBatch`; `store.deleteServicePresence(id:)`/`store.deleteQso(id:)`; `SwiftDataStoreImporter.uuid`. ✓
- Known-deferred: import cw-store-first; on-device bulk smoke (device now unlocked — runnable).

# QSO Write Cutover W1 (Interactive Writes) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`).

**Goal:** Extend the W0 `QSOWriteSink` seam with a general `upsert`, refactor `setHidden` to use it, and route the two interactive single-QSO write sites (`logQSO`, `QSOEditSheet.save`) through it so cw-store is written canonically/first in `on` mode.

**Architecture:** `upsert(_:in:)` writes cw-store (the QSO + its ServicePresence) first, then a mirror-suppressed SwiftData save; `off`/`shadow` just save. A static `commitUpsert(_:in:)` routes seam-or-legacy. The contact-logging side-effects keep the W0 ordering (model mutations before the commit, external pushes after success).

**Tech Stack:** Swift 6 / SwiftData / `CarrierWaveData` / `CwFfi` `FieldStore` / XCTest.

**Spec:** [W1 design](2026-06-16-qso-cutover-W1-interactive-writes-design.md)

---

## Task 1: Extend `QSOWriteSink` (upsert + commitUpsert), refactor setHidden, tests

**Files:**
- Modify: `swift/ios/CarrierWave/Services/RustStore/QSOWriteSink.swift`
- Test: `swift/ios/CarrierWaveTests/RustStore/QSOWriteSinkTests.swift`

- [ ] **Step 1: Write the failing tests** — append to the `QSOWriteSinkTests` class:

```swift
    /// `on` mode: a freshly-inserted QSO (with a ServicePresence) lands in the cw-store
    /// base set + SwiftData via the general upsert, mirror suppressed (no duplicate).
    func testOnModeUpsertWritesNewQSOToCwStore() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let store = try FieldStore.openInMemory(key: "on-upsert")
        let mirror = CwStoreMirror(store: store)
        mirror.start()
        defer { mirror.stop() }

        let qso = QSOFactory.generate(count: 1)[0]
        let presence = ServicePresence(serviceType: .qrz, isPresent: true, qso: qso)
        context.insert(qso)
        context.insert(presence)

        let sink = QSOWriteSink(store: store, mirror: mirror, modeProvider: { .on })
        try sink.upsert(qso, in: context)
        await mirror.drain()

        XCTAssertEqual(try Int(store.qsoCountQuery(query: "")), 1, "new QSO reached cw-store base set")
        XCTAssertEqual(try store.qsoCount(), 1, "no duplicate from an echo")
        XCTAssertEqual(try store.servicePresenceCount(), 1, "presence reached cw-store")
    }

    /// `on` mode: editing a field and upserting propagates the change to cw-store.
    func testOnModeUpsertPropagatesEdit() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let store = try FieldStore.openInMemory(key: "on-edit")
        let mirror = CwStoreMirror(store: store)
        mirror.start()
        defer { mirror.stop() }

        let qso = QSOFactory.generate(count: 1)[0]
        context.insert(qso)
        let sink = QSOWriteSink(store: store, mirror: mirror, modeProvider: { .on })
        try sink.upsert(qso, in: context)

        qso.name = "Edited Name"
        try sink.upsert(qso, in: context)
        await mirror.drain()

        let rows = try store.fetchQsosQuery(query: "", limit: 10, offset: 0)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.name, "Edited Name", "edited field propagated to cw-store")
    }
```

- [ ] **Step 2: Run; verify FAIL to compile** (`upsert` doesn't exist). `xc test-unit` (device must be unlocked; if locked, the user is verifying separately — at minimum confirm `xc build` fails to compile referencing `upsert`).

- [ ] **Step 3: Implement.** In `QSOWriteSink.swift`, add the `upsert` method and refactor `setHidden`/remove `writeHiddenToStore`. Replace the `setHidden` + `writeHiddenToStore` + `applyHiddenInMemory` block with:

```swift
    /// Apply a hidden-flag change, then commit via `upsert`.
    func setHidden(_ qso: QSO, hidden: Bool, in context: ModelContext) throws {
        applyHiddenInMemory(qso, hidden: hidden)
        try upsert(qso, in: context)
    }

    /// Commit a QSO insert/update. The caller has already inserted (new) or mutated
    /// (edit) the QSO in `context`. In `on` mode this writes cw-store FIRST (the QSO and
    /// its ServicePresence rows), then saves SwiftData with the mirror suppressed. Other
    /// modes just save (the unsuppressed mirror dual-writes in `shadow`). Throws if the
    /// canonical cw-store write fails — the caller must `rollback()`.
    func upsert(_ qso: QSO, in context: ModelContext) throws {
        if modeProvider() == .on {
            try writeUpsertToStore(qso)
            mirror?.beginSeamWrite()
            defer { mirror?.endSeamWrite() }
            try context.save()
        } else {
            try context.save()
        }
    }

    private func writeUpsertToStore(_ qso: QSO) throws {
        try store.upsertQso(qso: SwiftDataStoreImporter.project(qso))
        for presence in qso.servicePresence {
            try store.upsertServicePresence(item: SwiftDataStoreImporter.project(presence))
        }
    }

    private func applyHiddenInMemory(_ qso: QSO, hidden: Bool) {
        qso.isHidden = hidden
        guard hidden else {
            return
        }
        for presence in qso.servicePresence where presence.needsUpload {
            presence.needsUpload = false
        }
    }
```

Then add the static routing helper at the bottom of the file (outside the struct):

```swift
// MARK: - QSOWriteSink + Routing

extension QSOWriteSink {
    /// Route a QSO upsert through the active seam, or fall back to a plain SwiftData
    /// save when no seam is active (`off` mode / experiment disabled). The caller has
    /// already inserted/mutated the QSO in `context`.
    @MainActor
    static func commitUpsert(_ qso: QSO, in context: ModelContext) throws {
        if let sink = QSOWriteSinkRegistry.current {
            try sink.upsert(qso, in: context)
        } else {
            try context.save()
        }
    }
}
```

- [ ] **Step 4: Run tests; verify the 2 new tests PASS and the existing `setHidden`/suppression tests STILL PASS** (regression guard for the refactor). If the device is locked, confirm `xc build` is clean and note the test run is deferred to the user.

- [ ] **Step 5: Commit** — `git add` the two files; `git commit -m "Phase 4 (W1): QSOWriteSink.upsert + commitUpsert; setHidden delegates"`.

---

## Task 2: Route `logQSO` (insertAndFinalize) through the seam

**Files:**
- Modify: `swift/ios/CarrierWave/Services/LoggingSessionManager+QSOManagement.swift`

- [ ] **Step 1: Replace `insertAndFinalize(qso:session:)`** with:

```swift
    /// Insert QSO, update counters, persist (canonically to cw-store first in `on`
    /// mode), and trigger side effects. On a cw-store write failure the insert +
    /// counter increments are rolled back and the post-log side effects are skipped.
    private func insertAndFinalize(qso: QSO, session: LoggingSession) {
        modelContext.insert(qso)
        session.incrementQSOCount()
        incrementCurrentRoveStopQSOCount()
        markForUpload(qso)

        do {
            try QSOWriteSink.commitUpsert(qso, in: modelContext)
        } catch {
            modelContext.rollback()
            CwStoreWriteLog.shared.record("Log QSO failed: \(error.localizedDescription)")
            return
        }

        QSOLedger.append(qso)
        NotificationCenter.default.post(
            name: .didLogQSO,
            object: nil,
            userInfo: ["callsign": qso.callsign]
        )
        writeSessionToWidget(session, lastCallsign: qso.callsign)
        updateLiveActivity(lastCallsign: qso.callsign)

        Task { [weak self] in
            await self?.processActivityForQSO(qso)
        }
    }
```

Only the persistence call (`try? modelContext.save()` → seam commit + rollback/log + early return) and the doc comment change; the insert/counter/markForUpload before and the side effects after keep their exact order and content. Do not touch `logQSO` itself.

- [ ] **Step 2:** `xc build` → BUILD OK (build does not need the device unlocked).
- [ ] **Step 3: Commit** — `git commit -m "Phase 4 (W1): route logQSO through QSOWriteSink"`.

---

## Task 3: Route `QSOEditSheet.save` through the seam

**Files:**
- Modify: `swift/ios/CarrierWave/Views/Logs/QSOEditSheet+Save.swift`

- [ ] **Step 1:** In `save()`, replace the single line `try? modelContext.save()` (the one right after `qso.modifiedAt = Date()`) with:

```swift
        do {
            try QSOWriteSink.commitUpsert(qso, in: modelContext)
        } catch {
            modelContext.rollback()
            CwStoreWriteLog.shared.record("Edit QSO failed: \(error.localizedDescription)")
            return
        }
```

Leave everything else in `save()` unchanged (the `applyXFields()` calls before it, and the `refreshCallsignLookup` / haptic / `.didLogQSO` post / `onSave()` / `dismiss()` after it). Do NOT change `refreshCallsignLookup`'s own `try? context.save()` (best-effort background enrichment; the running mirror still carries it to cw-store in `on` mode).

- [ ] **Step 2:** `xc build` → BUILD OK.
- [ ] **Step 3: Commit** — `git commit -m "Phase 4 (W1): route QSOEditSheet.save through QSOWriteSink"`.

---

## Task 4: Changelog + cutover-doc note

**Files:**
- Modify: `CHANGELOG.md` (append to the existing `[Unreleased] → ### Changed` QSO Rust Store bullet area — add a new bullet, do NOT create a second `### Changed`)
- Modify: `docs/plans/2026-06-14-qso-rust-store-cutover-design.md` (note W1)

- [ ] **Step 1: Changelog** — under the existing `### Changed` in `[Unreleased]`, add:

```markdown
- **iOS Field — QSO Rust Store write-cutover W1 (interactive writes), hidden experiment.** Logging a new QSO and editing one now write the Rust cw-store first/canonically in `on` mode (same seam + suppression as hide/unhide); `off`/`shadow` unchanged.
```

- [ ] **Step 2: Cutover doc** — update the W0 note added earlier to also mark W1 (code-complete, on-device verification pending), keeping the W2 follow-up.

- [ ] **Step 3: Commit** — `git commit -m "Phase 4 (W1): changelog + cutover-doc note"`.

---

## Self-Review

- Seam `upsert` + `commitUpsert` + `setHidden` delegation → Task 1; tests cover new-QSO + edit propagation + the refactor regression. ✓
- logQSO routed, side-effect ordering preserved (model mutations before commit, external pushes after, rollback+skip on failure) → Task 2. ✓
- Edit routed; secondary `refreshCallsignLookup` save intentionally left → Task 3. ✓
- Consumer-snapshot unwind explicitly deferred (design doc) — not attempted here. ✓
- Type consistency: `upsert(_:in:)`, `commitUpsert(_:in:)`, `writeUpsertToStore`, `applyHiddenInMemory` names consistent across tasks; `CwStoreWriteLog.shared.record` matches W0. ✓
- Known-deferred: on-device test run (device locked this session).

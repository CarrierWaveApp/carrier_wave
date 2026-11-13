# QSO Write Seam (W0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Rust `cw-store` authoritative for QSO `hide`/`unhide` writes in `on` mode while SwiftData stays a downstream sync adapter — building the `QSOWriteSink` seam and the `CwStoreMirror` echo-suppression primitive that the later write slices (W1/W2) reuse.

**Architecture:** A `@MainActor` `QSOWriteSink` funnels hide/unhide. In `on` mode it writes cw-store **first** (canonical; aborts on failure), then mutates + saves SwiftData with `CwStoreMirror` suppressed so the save feeds CloudKit without echoing back into cw-store. In `off`/`shadow` it falls through to today's SwiftData-first behavior (and in `shadow` the unsuppressed mirror dual-writes as before). All gated by the existing `cwStoreQSOMode` flag.

**Tech Stack:** Swift 6 / SwiftData / SwiftUI (iOS app target `CarrierWave`), `CarrierWaveData` SPM package, Rust `cw-store` via the `CwFfi` UniFFI binding (`FieldStore`), XCTest.

**Spec:** [W0 design](2026-06-16-qso-cutover-W0-write-seam-design.md)

---

## File Structure

**Create (app target — `swift/ios/CarrierWave/Services/RustStore/`):**
- `QSOWriteSink.swift` — the seam (`QSOWriteSink` struct + `QSOWriteSinkRegistry` enum). One responsibility: route a QSO hide/unhide across cw-store + SwiftData by mode.
- `CwStoreWriteLog.swift` — tiny `@MainActor` in-memory ring buffer for surfacing write failures in the Data Migration screen.

**Create (test target — `swift/ios/CarrierWaveTests/RustStore/`):**
- `QSOWriteSinkTests.swift` — unit tests for the seam + suppression.

**Modify:**
- `swift/ios/CarrierWave/Services/RustStore/CwStoreMirror.swift` — add `beginSeamWrite()`/`endSeamWrite()` + suppress QSO/ServicePresence capture while a seam write is in flight.
- `swift/packages/CarrierWaveData/Sources/CarrierWaveData/RustStore/QSOReadSource.swift` — add `CwStoreQSOMode.current` (reads the `@AppStorage` key from `UserDefaults`).
- `swift/ios/CarrierWave/CarrierWaveApp.swift` — in `applyQSOMirrorMode`, build + register the `QSOWriteSink` (store + mirror) for `on`/`shadow`; clear it on `off`.
- `swift/ios/CarrierWave/Services/LoggingSessionManager+QSOManagement.swift` — route `hideQSO`/`unhideQSO` through the seam.
- `swift/ios/CarrierWave/Views/Settings/ExperimentsView.swift` — show recent `CwStoreWriteLog` entries in the Data Migration section.

**Key existing APIs this plan calls (verified):**
- `FieldStore.openInMemory(key:)`, `store.upsertQso(qso: FfiQso)`, `store.upsertServicePresence(item: FfiServicePresence)`, `store.qsoCount() -> Int64`, `store.qsoCountQuery(query:) -> Int64` (empty query = base non-hidden set).
- `SwiftDataStoreImporter.project(_ qso: QSO) -> FfiQso` and `project(_ presence: ServicePresence) -> FfiServicePresence` (both `nonisolated public static`).
- `FfiQso` is a struct with `var isHidden: Bool`; `FfiServicePresence` has `var needsUpload: Bool`.
- `CwStoreMirror` (app target, `nonisolated final class … @unchecked Sendable`, `NSLock`-guarded), `CwStoreMirrorRegistry.current` (`@MainActor weak`).
- `LoggingSessionManager` is `@MainActor final class` with `let modelContext: ModelContext`.
- `QSOFactory.generate(count:)` (test helper).

---

## Task 1: `CwStoreQSOMode.current`

**Files:**
- Modify: `swift/packages/CarrierWaveData/Sources/CarrierWaveData/RustStore/QSOReadSource.swift`
- Test: `swift/ios/CarrierWaveTests/RustStore/QSOWriteSinkTests.swift` (covered indirectly via seam tests; no standalone test here — this is a trivial accessor)

- [ ] **Step 1: Add the accessor**

In `QSOReadSource.swift`, inside the `CwStoreQSOMode` enum, after `appStorageKey`:

```swift
    /// The current rollout state read from `UserDefaults` (the backing store for
    /// the `@AppStorage("cwStoreQSOMode")` toggle). Lets non-View code (the write
    /// seam, `LoggingSessionManager`) route by mode without a SwiftUI binding.
    public static var current: CwStoreQSOMode {
        guard let raw = UserDefaults.standard.string(forKey: appStorageKey),
              let mode = CwStoreQSOMode(rawValue: raw)
        else {
            return .off
        }
        return mode
    }
```

- [ ] **Step 2: Commit**

```bash
git add swift/packages/CarrierWaveData/Sources/CarrierWaveData/RustStore/QSOReadSource.swift
git commit -m "Phase 4 (W0): CwStoreQSOMode.current accessor for non-View routing"
```

---

## Task 2: `CwStoreMirror` echo-suppression primitive

**Files:**
- Modify: `swift/ios/CarrierWave/Services/RustStore/CwStoreMirror.swift`
- Test: `swift/ios/CarrierWaveTests/RustStore/QSOWriteSinkTests.swift`

- [ ] **Step 1: Write the failing test**

Create `swift/ios/CarrierWaveTests/RustStore/QSOWriteSinkTests.swift`:

```swift
import CarrierWaveCore
import SwiftData
import XCTest
@testable import CarrierWave
@testable import CarrierWaveData

@MainActor
final class QSOWriteSinkTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema([QSO.self, ServicePresence.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    /// While a seam write is in flight, the mirror must NOT capture QSO changes —
    /// otherwise the seam's SwiftData save would echo back into cw-store.
    func testSeamWriteSuppressesMirrorCapture() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let store = try FieldStore.openInMemory(key: "suppress")
        let mirror = CwStoreMirror(store: store)
        mirror.start()
        defer { mirror.stop() }

        mirror.beginSeamWrite()
        context.insert(QSOFactory.generate(count: 1)[0])
        try context.save()
        mirror.endSeamWrite()
        await mirror.drain()

        XCTAssertEqual(try store.qsoCount(), 0, "capture must be skipped during a seam write")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xc test-unit` (or the Simulator scheme per memory `test-harness-device-vs-sim`).
Expected: FAIL to compile — `beginSeamWrite`/`endSeamWrite` do not exist on `CwStoreMirror`.

- [ ] **Step 3: Add the suppression state + API to `CwStoreMirror`**

In `CwStoreMirror.swift`, add to the `// MARK: Private` stored properties (next to `lastWrite`):

```swift
    /// Nonzero while a `QSOWriteSink` seam write is committing on this thread. When
    /// set, `capture` skips QSO/ServicePresence changes so the seam's SwiftData save
    /// does not echo back into cw-store (the seam already wrote cw-store canonically).
    /// Guarded by `lock`. A depth counter (not a Bool) is robust to nested writes.
    private var seamWriteDepth = 0
```

Add to `// MARK: Internal` (after `drain()`):

```swift
    /// Raise the seam-origin guard before a seam-driven `ModelContext.save()`.
    func beginSeamWrite() {
        lock.withLock { seamWriteDepth += 1 }
    }

    /// Lower the seam-origin guard after a seam-driven save completes.
    func endSeamWrite() {
        lock.withLock { seamWriteDepth = max(0, seamWriteDepth - 1) }
    }
```

In `capture(from:)`, add at the very top (before `var batch = Pending()`):

```swift
        if lock.withLock({ seamWriteDepth > 0 }) {
            return Pending()
        }
```

(`capture` is called from `handleWillSave` *outside* the lock, so this nested `lock.withLock` does not deadlock — `NSLock` is taken and released here independently.)

- [ ] **Step 4: Run test to verify it passes**

Run: `xc test-unit` filtered to `QSOWriteSinkTests/testSeamWriteSuppressesMirrorCapture`.
Expected: PASS.

- [ ] **Step 5: Run the existing mirror tests to confirm no regression**

Run: `xc test-unit` filtered to `CwStoreMirrorTests`.
Expected: PASS (suppression is off by default; `seamWriteDepth == 0`).

- [ ] **Step 6: Commit**

```bash
git add swift/ios/CarrierWave/Services/RustStore/CwStoreMirror.swift swift/ios/CarrierWaveTests/RustStore/QSOWriteSinkTests.swift
git commit -m "Phase 4 (W0): CwStoreMirror seam-write suppression guard"
```

---

## Task 3: `CwStoreWriteLog` diagnostics surface

**Files:**
- Create: `swift/ios/CarrierWave/Services/RustStore/CwStoreWriteLog.swift`
- Test: `swift/ios/CarrierWaveTests/RustStore/QSOWriteSinkTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `QSOWriteSinkTests.swift` (inside the class):

```swift
    func testWriteLogCapsAtFifty() {
        let log = CwStoreWriteLog()
        for index in 0..<60 {
            log.record("entry \(index)")
        }
        XCTAssertEqual(log.entries.count, 50)
        XCTAssertTrue(log.entries.last?.contains("entry 59") ?? false)
        XCTAssertFalse(log.entries.first?.contains("entry 0") ?? true)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xc test-unit` filtered to `QSOWriteSinkTests/testWriteLogCapsAtFifty`.
Expected: FAIL to compile — `CwStoreWriteLog` does not exist.

- [ ] **Step 3: Create the log**

Create `swift/ios/CarrierWave/Services/RustStore/CwStoreWriteLog.swift`:

```swift
import UIKit

/// In-memory ring buffer of cw-store write-path diagnostics, surfaced in the
/// Data Migration screen. The write seam records failures here (the iOS logging
/// rule forbids `os_log`/`print` from app code). Capped so it never grows
/// unbounded. Not persisted — diagnostics for the current session only.
@MainActor
final class CwStoreWriteLog {
    static let shared = CwStoreWriteLog()

    private(set) var entries: [String] = []

    private let limit = 50

    func record(_ message: String) {
        let stamp = Date().formatted(date: .omitted, time: .standard)
        entries.append("\(stamp)  \(message)")
        if entries.count > limit {
            entries.removeFirst(entries.count - limit)
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xc test-unit` filtered to `QSOWriteSinkTests/testWriteLogCapsAtFifty`.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add swift/ios/CarrierWave/Services/RustStore/CwStoreWriteLog.swift swift/ios/CarrierWaveTests/RustStore/QSOWriteSinkTests.swift
git commit -m "Phase 4 (W0): CwStoreWriteLog diagnostics ring buffer"
```

---

## Task 4: `QSOWriteSink` seam + registry

**Files:**
- Create: `swift/ios/CarrierWave/Services/RustStore/QSOWriteSink.swift`
- Test: `swift/ios/CarrierWaveTests/RustStore/QSOWriteSinkTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `QSOWriteSinkTests.swift` (inside the class):

```swift
    /// `on` mode: hide writes the hidden state to cw-store (canonical) AND updates
    /// the SwiftData replica, with the mirror suppressed (no echo / no duplicate).
    func testOnModeHideWritesCwStoreAndSwiftData() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let store = try FieldStore.openInMemory(key: "on-hide")
        let mirror = CwStoreMirror(store: store)
        mirror.start()
        defer { mirror.stop() }

        // Seed one visible QSO into both stores (mirror carries it to cw-store).
        let qso = QSOFactory.generate(count: 1)[0]
        context.insert(qso)
        try context.save()
        await mirror.drain()
        XCTAssertEqual(try Int(store.qsoCountQuery(query: "")), 1)

        let sink = QSOWriteSink(store: store, mirror: mirror, modeProvider: { .on })
        try sink.setHidden(qso, hidden: true, in: context)
        await mirror.drain()

        XCTAssertEqual(try Int(store.qsoCountQuery(query: "")), 0, "hide reached cw-store (excluded from base set)")
        XCTAssertEqual(try store.qsoCount(), 1, "still one row — no duplicate from an echo")
        XCTAssertTrue(qso.isHidden, "SwiftData replica updated")
    }

    /// `on` mode: hide → unhide returns the row to the base (non-hidden) set.
    func testOnModeUnhideRoundTrips() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let store = try FieldStore.openInMemory(key: "on-unhide")
        let mirror = CwStoreMirror(store: store)
        mirror.start()
        defer { mirror.stop() }

        let qso = QSOFactory.generate(count: 1)[0]
        context.insert(qso)
        try context.save()
        await mirror.drain()

        let sink = QSOWriteSink(store: store, mirror: mirror, modeProvider: { .on })
        try sink.setHidden(qso, hidden: true, in: context)
        XCTAssertEqual(try Int(store.qsoCountQuery(query: "")), 0)

        try sink.setHidden(qso, hidden: false, in: context)
        XCTAssertEqual(try Int(store.qsoCountQuery(query: "")), 1)
        XCTAssertFalse(qso.isHidden)
    }

    /// `shadow` mode: the seam does NOT suppress the mirror, so the unsuppressed
    /// mirror dual-writes the hide to cw-store after the SwiftData save (today's
    /// shadow behavior — reads still come from SwiftData).
    func testShadowModeHideDualWritesViaMirror() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let store = try FieldStore.openInMemory(key: "shadow-hide")
        let mirror = CwStoreMirror(store: store)
        mirror.start()
        defer { mirror.stop() }

        let qso = QSOFactory.generate(count: 1)[0]
        context.insert(qso)
        try context.save()
        await mirror.drain()
        XCTAssertEqual(try Int(store.qsoCountQuery(query: "")), 1)

        let sink = QSOWriteSink(store: store, mirror: mirror, modeProvider: { .shadow })
        try sink.setHidden(qso, hidden: true, in: context)
        await mirror.drain()

        XCTAssertEqual(try Int(store.qsoCountQuery(query: "")), 0, "shadow mirror carried the hide to cw-store")
        XCTAssertTrue(qso.isHidden)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xc test-unit` filtered to `QSOWriteSinkTests`.
Expected: FAIL to compile — `QSOWriteSink` does not exist.

- [ ] **Step 3: Create the seam**

Create `swift/ios/CarrierWave/Services/RustStore/QSOWriteSink.swift`:

```swift
import CarrierWaveCore
import CarrierWaveData
import SwiftData
import UIKit

// MARK: - QSOWriteSinkRegistry

/// Main-actor handle to the live write seam so `LoggingSessionManager` can route
/// QSO mutations through cw-store in `on`/`shadow` mode. Set by
/// `CarrierWaveApp.applyQSOMirrorMode`; `nil` in `off` mode. Value type, so the
/// registry holds it by value (no weak/strong cycle).
@MainActor
enum QSOWriteSinkRegistry {
    static var current: QSOWriteSink?
}

// MARK: - QSOWriteSink

/// Funnels QSO hide/unhide writes, routed by `cwStoreQSOMode`:
/// - `on`: write cw-store FIRST (canonical — abort if it throws), then mutate the
///   SwiftData replica and save with `CwStoreMirror` suppressed so CloudKit still
///   picks up the change but the save does not echo back into cw-store.
/// - `shadow`/anything else: mutate SwiftData and save (the unsuppressed mirror
///   dual-writes in `shadow`). `off` mode never constructs a seam (registry is nil).
@MainActor
struct QSOWriteSink {
    let store: FieldStore
    let mirror: CwStoreMirror?
    var modeProvider: () -> CwStoreQSOMode = { CwStoreQSOMode.current }

    /// Apply a hidden-flag change to the data layer. The caller has already applied
    /// any non-store side effects (session counters, Live Activity) in memory; this
    /// method owns the cw-store write and the `context.save()` that commits them.
    /// Throws if the canonical cw-store write fails — the caller must `rollback()`.
    func setHidden(_ qso: QSO, hidden: Bool, in context: ModelContext) throws {
        if modeProvider() == .on {
            try writeHiddenToStore(qso, hidden: hidden) // canonical; throws → abort before SwiftData save
            mirror?.beginSeamWrite()
            defer { mirror?.endSeamWrite() }
            applyHiddenInMemory(qso, hidden: hidden)
            try context.save()
        } else {
            applyHiddenInMemory(qso, hidden: hidden)
            try context.save()
        }
    }

    /// Canonical cw-store write. Projects the (not-yet-mutated) QSO, overrides
    /// `isHidden`, and upserts. On hide, also clears `needsUpload` on the QSO's
    /// pending ServicePresence rows (matching the SwiftData behavior); on unhide it
    /// leaves presence untouched.
    private func writeHiddenToStore(_ qso: QSO, hidden: Bool) throws {
        var ffi = SwiftDataStoreImporter.project(qso)
        ffi.isHidden = hidden
        try store.upsertQso(qso: ffi)
        guard hidden else {
            return
        }
        for presence in qso.servicePresence where presence.needsUpload {
            var projected = SwiftDataStoreImporter.project(presence)
            projected.needsUpload = false
            try store.upsertServicePresence(item: projected)
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
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xc test-unit` filtered to `QSOWriteSinkTests`.
Expected: PASS (all five tests).

- [ ] **Step 5: Commit**

```bash
git add swift/ios/CarrierWave/Services/RustStore/QSOWriteSink.swift swift/ios/CarrierWaveTests/RustStore/QSOWriteSinkTests.swift
git commit -m "Phase 4 (W0): QSOWriteSink seam (cw-store-first hide/unhide) + tests"
```

---

## Task 5: Register the seam in `applyQSOMirrorMode`

**Files:**
- Modify: `swift/ios/CarrierWave/CarrierWaveApp.swift` (around lines 474-498)

There is no unit test for app wiring (it depends on the App Group store + container lifecycle); this is verified on-device in Task 7.

- [ ] **Step 1: Register/clear the seam alongside the mirror**

In `applyQSOMirrorMode(_:)`, replace the body with:

```swift
    func applyQSOMirrorMode(_ mode: CwStoreQSOMode) async {
        guard ExperimentalFeature.isEnabled(.rustStoreQSO) else {
            return
        }
        if mode == .off {
            qsoMirror?.stop()
            qsoMirror = nil
            CwStoreMirrorRegistry.current = nil
            QSOWriteSinkRegistry.current = nil
        } else if qsoMirror == nil {
            do {
                let store = try await CwStoreProvider.shared.store()
                let mirror = CwStoreMirror(store: store)
                mirror.start()
                qsoMirror = mirror
                CwStoreMirrorRegistry.current = mirror
                QSOWriteSinkRegistry.current = QSOWriteSink(store: store, mirror: mirror)
                let container = sharedModelContainer
                let version = Bundle.main
                    .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
                _ = try await CwStoreImportCoordinator
                    .appGroup(version: version).runIfNeeded(from: container)
            } catch {}
        }
    }
```

(The seam reads mode live via `CwStoreQSOMode.current`, so it is correct for both `shadow` and `on` without rebuilding when the mode toggles between them.)

- [ ] **Step 2: Build to verify it compiles**

Run: `xc build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add swift/ios/CarrierWave/CarrierWaveApp.swift
git commit -m "Phase 4 (W0): register QSOWriteSink with the mirror lifecycle"
```

---

## Task 6: Route `hideQSO`/`unhideQSO` through the seam

**Files:**
- Modify: `swift/ios/CarrierWave/Services/LoggingSessionManager+QSOManagement.swift` (`hideQSO` lines 122-138, `unhideQSO` lines 141-144)

`hideQSO`/`unhideQSO` stay synchronous (the seam holds a synchronous `FieldStore`), so the 4 call sites in `LoggerView+*` need no changes.

- [ ] **Step 1: Rewrite `hideQSO`**

Replace `hideQSO(_:)` with:

```swift
    /// Hide a QSO (soft delete). Routes the data write through `QSOWriteSink` when a
    /// cw-store seam is active (`on`/`shadow`); otherwise the legacy SwiftData path.
    /// Session counters / Live Activity are applied in memory first and ride the
    /// seam's `save()`. On a cw-store failure the context is rolled back and the
    /// failure recorded for the Data Migration diagnostics.
    func hideQSO(_ qso: QSO) {
        if let session = activeSession, qso.loggingSessionId == session.id {
            session.decrementQSOCount()
            decrementRoveStopQSOCount(for: qso)
            updateLiveActivity()
            writeSessionToWidget(session)
        }

        do {
            if let sink = QSOWriteSinkRegistry.current {
                try sink.setHidden(qso, hidden: true, in: modelContext)
            } else {
                qso.isHidden = true
                for presence in qso.servicePresence where presence.needsUpload {
                    presence.needsUpload = false
                }
                try modelContext.save()
            }
        } catch {
            modelContext.rollback()
            CwStoreWriteLog.shared.record("Hide failed: \(error.localizedDescription)")
        }
    }
```

- [ ] **Step 2: Rewrite `unhideQSO`**

Replace `unhideQSO(_:)` with:

```swift
    /// Unhide a previously hidden QSO. Same routing as `hideQSO`.
    func unhideQSO(_ qso: QSO) {
        do {
            if let sink = QSOWriteSinkRegistry.current {
                try sink.setHidden(qso, hidden: false, in: modelContext)
            } else {
                qso.isHidden = false
                try modelContext.save()
            }
        } catch {
            modelContext.rollback()
            CwStoreWriteLog.shared.record("Unhide failed: \(error.localizedDescription)")
        }
    }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xc build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Run the full RustStore + manager test suites**

Run: `xc test-unit` filtered to `QSOWriteSinkTests` and `CwStoreMirrorTests`.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add swift/ios/CarrierWave/Services/LoggingSessionManager+QSOManagement.swift
git commit -m "Phase 4 (W0): route hide/unhide through QSOWriteSink"
```

---

## Task 7: Surface write failures in the Data Migration screen + device verification

**Files:**
- Modify: `swift/ios/CarrierWave/Views/Settings/ExperimentsView.swift` (Data Migration section)

- [ ] **Step 1: Show recent write-log entries**

In `ExperimentsView.swift`, in the Data Migration section (near the parity/sweep status rows), add a row that renders the most recent `CwStoreWriteLog.shared.entries`:

```swift
                if !CwStoreWriteLog.shared.entries.isEmpty {
                    DisclosureGroup("cw-store write log") {
                        ForEach(Array(CwStoreWriteLog.shared.entries.suffix(10).enumerated()), id: \.offset) { _, entry in
                            Text(entry)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
```

- [ ] **Step 2: Build**

Run: `xc build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Device verification (manual)**

Run: `xc deploy`. Then, in the app:
1. Settings → Experiments → enable **QSO Rust Store**; set Data Migration mode to **on**.
2. Hide a QSO from the Logbook (or Logger delete-to-hide). Expected: it leaves the list (list reads cw-store in `on` mode).
3. Unhide it from Settings → All Hidden QSOs. Expected: it returns to the Logbook.
4. Run **Run QSO Parity Check**. Expected: "QSO parity OK".
5. (If a second device with the same iCloud account is available) confirm the hidden state propagates via CloudKit; then set mode to **off** and confirm the QSO is still hidden in SwiftData.

- [ ] **Step 4: Commit**

```bash
git add swift/ios/CarrierWave/Views/Settings/ExperimentsView.swift
git commit -m "Phase 4 (W0): surface cw-store write log in Data Migration"
```

---

## Task 8: Update changelog + cutover docs

**Files:**
- Modify: `CHANGELOG.md` (under `[Unreleased]`)
- Modify: `docs/plans/2026-06-14-qso-rust-store-cutover-design.md` (note W0 started/done in the decomposition section)

- [ ] **Step 1: Changelog**

Under `[Unreleased]` add (developer-facing; this is behind a hidden experiment so it does NOT need a What's New entry):

```markdown
### Changed
- QSO Rust Store (hidden experiment): in `on` mode, hide/unhide now write the Rust
  cw-store as the canonical store and project to SwiftData for CloudKit sync (write
  cutover W0).
```

- [ ] **Step 2: Note W0 in the cutover decomposition**

In `2026-06-14-qso-rust-store-cutover-design.md`, in the "Remaining cutover work" / next-steps area, mark the write-cutover as started with a pointer:

```markdown
- **Write-cutover W0 (DONE 2026-06-16):** `QSOWriteSink` seam + `CwStoreMirror`
  echo-suppression; hide/unhide write cw-store first in `on` mode, SwiftData kept as
  CloudKit adapter. See [W0 design](2026-06-16-qso-cutover-W0-write-seam-design.md) /
  [W0 plan](2026-06-16-qso-cutover-W0-write-seam-plan.md). W1 (interactive writes),
  W2 (bulk) follow.
```

- [ ] **Step 3: Commit**

```bash
git add CHANGELOG.md docs/plans/2026-06-14-qso-rust-store-cutover-design.md
git commit -m "Phase 4 (W0): changelog + cutover-doc note"
```

---

## Self-Review

**Spec coverage:**
- `QSOWriteSink` seam routed by mode → Task 4. ✓
- cw-store-first canonical write, abort on failure → Task 4 (`setHidden` `on` branch) + Task 6 (`rollback` on catch). ✓
- Inline SwiftData projection (no async reverse mirror) → Task 4. ✓
- Echo-suppression guard honored by `CwStoreMirror`, retained for inbound → Task 2 (`seamWriteDepth` skips capture; inbound never raises the guard). ✓
- `hide`/`unhide` as the cutover target; other writes untouched → Task 6 only edits hide/unhide. ✓
- `off`/`shadow` keep today's behavior; `shadow` mirror still dual-writes → Task 4 `else` branch + `testShadowModeHideDualWritesViaMirror`. ✓
- Failure logged to a diagnostics surface → Task 3 (`CwStoreWriteLog`) + Task 7 (display). ✓
- Reads stay fresh without a drain barrier for seam writes → seam writes cw-store synchronously before returning; no code needed (documented). ✓
- Testing: unit (suppression, on-mode hide, unhide round-trip, shadow dual-write) + device steps → Tasks 2/4/7. ✓

**Placeholder scan:** No TBD/TODO; every code step shows complete code. ✓

**Type consistency:** `beginSeamWrite()`/`endSeamWrite()` (Task 2) match calls in `QSOWriteSink.setHidden` (Task 4). `QSOWriteSink(store:mirror:)` init (Task 4, default `modeProvider`) matches the call in Task 5 and the 3-arg form in tests (Task 4). `setHidden(_:hidden:in:)` signature matches Task 6 call sites. `CwStoreWriteLog.shared.record(_:)` (Task 3) matches Task 6/7 usage. `CwStoreQSOMode.current` (Task 1) used as the seam's default `modeProvider` (Task 4). ✓

**Known seam (documented, intentionally not unit-tested):** the cw-store-write-failure → `rollback()` path is not unit-tested because `FieldStore` is a concrete UniFFI type with no failure-injection seam; it is covered by the device steps and the rare-failure analysis in the spec. The pre-existing `QuickEntryTimeTests` failure noted in the C handoff is unrelated.

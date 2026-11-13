# QSO Cutover — Sub-project A: Infrastructure + Count Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the reusable SwiftData→Rust cutover pipeline (dual-write mirror, shared store accessor, read seam, parity probe, flag) and prove it end-to-end with a raw QSO-count parity check, behind an off-by-default experiment.

**Architecture:** A dedicated `ModelContext.didSave`/`willSave` observer (`CwStoreMirror`) projects QSO inserts/updates/deletes into the shared encrypted Rust store on a serial background actor. A `QSOReadSource` seam routes the QSO count between SwiftData and Rust based on a tri-state mode; `QSOParityProbe` compares them. SwiftData stays the system of record — the Rust store is a read mirror only.

**Tech Stack:** Rust (`cw-store`/`cw-ffi`, rusqlite, UniFFI), Swift 6 (SwiftData, `@MainActor`/actors, XCTest), the existing `CwFfi.xcframework` toolchain.

**Spec:** `docs/plans/2026-06-14-qso-rust-store-cutover-design.md`

**Conventions:**
- Rust: hand-formatted, NO `cargo fmt`. Gate: `cargo test --workspace` + `cargo clippy --workspace --all-targets`.
- Swift: hooks run SwiftFormat/SwiftLint on edit. Build via `~/.claude/skills/xcode-build/scripts/xc` or `xcodebuild`. Never `print`/`os_log` — use existing in-app log surfaces.
- iOS target defaults to `@MainActor` isolation (`SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`); non-UI types need explicit `nonisolated`.
- Commit after each task. Regenerated `Vendored/CwFfi.xcframework` is gitignored; `CwFfi+Generated.swift` is tracked.

---

## File structure

**Rust (new/modified):**
- Modify: `rust/cw-core/cw-store/src/qso.rs` — add `delete_qso(id)` + test.
- Modify: `rust/cw-core/cw-ffi/src/lib.rs` — add `delete_qso(id)` FFI firing `notify(.Delete)` + test.
- Regenerate: `CwFfi.xcframework` + `swift/packages/CarrierWaveCore/Sources/CarrierWaveCwFfi/CwFfi+Generated.swift`.

**Swift — CarrierWaveData package (new):**
- Create: `Sources/CarrierWaveData/RustStore/CwStoreProvider.swift` — shared long-lived `FieldStore` accessor (App Group path + device key).
- Create: `Sources/CarrierWaveData/RustStore/QSOReadSource.swift` — seam protocol + SwiftData/Rust/Routing impls (count only this slice).
- Create: `Sources/CarrierWaveData/RustStore/QSOParityProbe.swift` — count comparison + result type.
- Test: `Tests/CarrierWaveDataTests/RustStore/QSOReadSourceTests.swift`, `.../QSOParityProbeTests.swift`.

**Swift — CarrierWaveData package (modified):**
- Modify: `Sources/CarrierWaveData/Utilities/ExperimentalFeature.swift` — add `rustStoreQSO` (hidden).
- Modify: `Sources/CarrierWaveData/Import/CwStoreImportCoordinator.swift` — reuse `CwStoreProvider` path/key helpers (DRY; no behavior change).

**Swift — iOS app target (new):**
- Create: `CarrierWave/Services/RustStore/CwStoreMirror.swift` — `didSave`/`willSave` observer.
- Create: `CarrierWave/Services/RustStore/CwStoreMirrorActor.swift` — serial dual-write actor.
- Test: `CarrierWaveTests/RustStore/CwStoreMirrorTests.swift`.

**Swift — iOS app target (modified):**
- Modify: `CarrierWave/Views/Settings/ExperimentsView.swift` — mode picker + "Run QSO parity check" in Data Migration.
- Modify: `CarrierWave/CarrierWaveApp.swift` — start/stop `CwStoreMirror` per mode.

**Shared mode setting:** `@AppStorage("cwStoreQSOMode")` — raw `String` enum `CwStoreQSOMode { off, shadow, on }` defined in `QSOReadSource.swift`.

---

## Task 1: Rust `delete_qso` in `cw-store`

**Files:**
- Modify: `rust/cw-core/cw-store/src/qso.rs`

- [ ] **Step 1: Write the failing test** (append inside the existing `#[cfg(test)] mod tests`)

```rust
#[test]
fn delete_qso_removes_row_and_is_idempotent() {
    let store = Store::open_in_memory("k").unwrap();
    store.upsert_qso(&sample_qso("11111111-1111-1111-1111-111111111111")).unwrap();
    assert_eq!(store.qso_count().unwrap(), 1);

    store.delete_qso("11111111-1111-1111-1111-111111111111").unwrap();
    assert_eq!(store.qso_count().unwrap(), 0);

    // Deleting a missing id is a no-op, not an error.
    store.delete_qso("no-such-id").unwrap();
    assert_eq!(store.qso_count().unwrap(), 0);
}
```

> Note: confirm the existing test helper is named `sample_qso(&str)`. If the helper differs, match the existing name/signature used by the other `qso.rs` tests.

- [ ] **Step 2: Run it to confirm it fails**

Run: `cd rust/cw-core && cargo test -p cw-store delete_qso_removes_row 2>&1 | tail -20`
Expected: FAIL — `no method named delete_qso`.

- [ ] **Step 3: Implement `delete_qso`** (add as a method in `impl Store`, next to `upsert_qso`)

```rust
/// Delete a QSO by id. Missing id is a no-op (idempotent).
pub fn delete_qso(&self, id: &str) -> Result<()> {
    self.conn
        .execute("DELETE FROM qso WHERE id = ?1", rusqlite::params![id])?;
    Ok(())
}
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `cd rust/cw-core && cargo test -p cw-store delete_qso_removes_row 2>&1 | tail -20`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add rust/cw-core/cw-store/src/qso.rs
git commit -m "Phase 4: cw-store delete_qso (QSO cutover infra)

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 2: FFI `delete_qso` firing `notify(.Delete)`

**Files:**
- Modify: `rust/cw-core/cw-ffi/src/lib.rs` (the `#[uniffi::export] impl FieldStore` block containing `upsert_qso`)

- [ ] **Step 1: Write the failing test** (add to the `#[cfg(test)] mod tests` in `lib.rs`, mirroring the existing upsert/notify test pattern that asserts `change.table == FfiStoreTable::Qso`)

```rust
#[test]
fn delete_qso_fires_delete_notification() {
    let store = FieldStore::open_in_memory("k".to_string()).unwrap();
    store.upsert_qso(sample_qso("22222222-2222-2222-2222-222222222222")).unwrap();

    let fired = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
    let observer = std::sync::Arc::new(TestObserver { // existing test observer type in this module
        fired: fired.clone(),
        expect: FfiChangeKind::Delete,
    });
    let token = store.add_observer(observer);

    store.delete_qso("22222222-2222-2222-2222-222222222222".to_string()).unwrap();
    assert!(fired.load(std::sync::atomic::Ordering::SeqCst));
    assert_eq!(store.qso_count().unwrap(), 0);
    store.remove_observer(token);
}
```

> Note: reuse the existing test-observer scaffolding already in `lib.rs`'s test module (the one used by the upsert-notify test). If its shape differs, match it — do not introduce a second observer type.

- [ ] **Step 2: Run it to confirm it fails**

Run: `cd rust/cw-core && cargo test -p cw-ffi delete_qso_fires 2>&1 | tail -20`
Expected: FAIL — `no method named delete_qso`.

- [ ] **Step 3: Implement the FFI method** (in the same `impl FieldStore` block as `upsert_qso`, mirroring its lock-then-notify shape — lock released before `notify`)

```rust
pub fn delete_qso(&self, id: String) -> Result<(), CwError> {
    {
        let store = self.inner.lock().expect("store mutex poisoned");
        store.delete_qso(&id)?;
    }
    self.notify(FfiStoreChange { table: FfiStoreTable::Qso, kind: FfiChangeKind::Delete });
    Ok(())
}
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `cd rust/cw-core && cargo test -p cw-ffi delete_qso_fires 2>&1 | tail -20`
Expected: PASS.

- [ ] **Step 5: Workspace gate**

Run: `cd rust/cw-core && cargo test --workspace 2>&1 | grep -E "test result|FAILED" | grep -v "0 passed; 0 failed" && cargo clippy --workspace --all-targets 2>&1 | tail -3`
Expected: all suites pass, clippy clean.

- [ ] **Step 6: Commit**

```bash
git add rust/cw-core/cw-ffi/src/lib.rs
git commit -m "Phase 4: cw-ffi delete_qso fires notify(.Delete)

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 3: Regenerate xcframework + bindings

**Files:**
- Regenerate: `CwFfi.xcframework`, `swift/packages/CarrierWaveCore/Sources/CarrierWaveCwFfi/CwFfi+Generated.swift`

- [ ] **Step 1: Build the xcframework**

Run: `cd rust/cw-core && ./scripts/build-xcframework.sh 2>&1 | tail -15`
Expected: ends with `✓ Swift bindings → ... CwFfi+Generated.swift (staged)`.

- [ ] **Step 2: Confirm the new binding exists**

Run: `rg -n "func deleteQso" swift/packages/CarrierWaveCore/Sources/CarrierWaveCwFfi/CwFfi+Generated.swift`
Expected: a `func deleteQso(id: String) throws` line.

- [ ] **Step 3: Commit the tracked binding** (the `Vendored/` xcframework is gitignored)

```bash
git add swift/packages/CarrierWaveCore/Sources/CarrierWaveCwFfi/CwFfi+Generated.swift
git commit -m "Phase 4: regenerate bindings for delete_qso

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 4: `CwStoreProvider` — shared `FieldStore` accessor

**Files:**
- Create: `swift/packages/CarrierWaveData/Sources/CarrierWaveData/RustStore/CwStoreProvider.swift`
- Test: `swift/packages/CarrierWaveData/Tests/CarrierWaveDataTests/RustStore/CwStoreProviderTests.swift`

A single long-lived `FieldStore` for the App Group store, shared by the importer, mirror, and read source (the observer registry + single-writer mutex live on one instance). Centralizes the path + device-key logic currently inline in `CwStoreImportCoordinator`.

- [ ] **Step 1: Write the failing test**

```swift
import CarrierWaveCore
import XCTest
@testable import CarrierWaveData

final class CwStoreProviderTests: XCTestCase {
    func testInMemoryProviderOpensAndReuses() async throws {
        let provider = CwStoreProvider(opener: { try FieldStore.openInMemory(key: "test") })
        let first = try await provider.store()
        let second = try await provider.store()
        XCTAssertTrue(first === second, "provider must reuse one FieldStore instance")
        XCTAssertEqual(try first.qsoCount(), 0)
    }
}
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `cd swift/packages/CarrierWaveData && swift test --filter CwStoreProviderTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'CwStoreProvider'`.

- [ ] **Step 3: Implement `CwStoreProvider`**

```swift
import CarrierWaveCore
import Foundation
import Security

/// Single long-lived FieldStore for the shared App Group cw-store. The importer,
/// mirror, and read source all use this one instance (the observer registry and
/// single-writer mutex must be shared). `opener` is injectable for tests.
public actor CwStoreProvider {
    public static let shared = CwStoreProvider()

    private let opener: @Sendable () throws -> FieldStore
    private var opened: FieldStore?

    public init(opener: @escaping @Sendable () throws -> FieldStore = CwStoreProvider.appGroupOpener) {
        self.opener = opener
    }

    public func store() throws -> FieldStore {
        if let opened { return opened }
        let store = try opener()
        opened = store
        return store
    }

    /// Opens the on-disk App Group store with the device-local SQLCipher key.
    public static let appGroupOpener: @Sendable () throws -> FieldStore = {
        let url = try appGroupStoreURL()
        return try FieldStore.open(path: url.path, key: localEncryptionKey())
    }

    static func appGroupStoreURL(appGroupID: String = "group.com.jsvana.FullDuplex") throws -> URL {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        else {
            throw CwStoreImportError.appGroupUnavailable(appGroupID)
        }
        return container.appendingPathComponent("cw-store.db")
    }

    static func localEncryptionKey() throws -> String {
        let keychain = KeychainHelper.shared
        if let existing = try? keychain.readString(for: KeychainHelper.Keys.cwStoreEncryptionKey),
           !existing.isEmpty {
            return existing
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw CwStoreImportError.keyGenerationFailed(status)
        }
        let key = Data(bytes).base64EncodedString()
        try keychain.save(key, for: KeychainHelper.Keys.cwStoreEncryptionKey)
        return key
    }
}
```

> Note: this moves the path/key logic out of `CwStoreImportCoordinator`. In a follow-up step (Task 4b) update the coordinator to call `CwStoreProvider.appGroupStoreURL()` / `localEncryptionKey()` so there is one copy. Verify `FieldStore` is a reference type (UniFFI objects are classes) so `===` is valid; it is.

- [ ] **Step 4: Run the test to confirm it passes**

Run: `cd swift/packages/CarrierWaveData && swift test --filter CwStoreProviderTests 2>&1 | tail -20`
Expected: PASS.

- [ ] **Step 4b: DRY the coordinator**

In `CwStoreImportCoordinator.swift`, replace the private `localEncryptionKey()` body and the App Group URL construction in `appGroup(...)` with calls to `CwStoreProvider.localEncryptionKey()` and `CwStoreProvider.appGroupStoreURL(appGroupID:)`. Run the existing importer tests:

Run: `cd swift/packages/CarrierWaveData && swift test --filter "Import" 2>&1 | grep -iE "passed|failed" | tail -5`
Expected: import suites still pass.

- [ ] **Step 5: Commit**

```bash
git add swift/packages/CarrierWaveData/Sources/CarrierWaveData/RustStore/CwStoreProvider.swift \
        swift/packages/CarrierWaveData/Tests/CarrierWaveDataTests/RustStore/CwStoreProviderTests.swift \
        swift/packages/CarrierWaveData/Sources/CarrierWaveData/Import/CwStoreImportCoordinator.swift
git commit -m "Phase 4: CwStoreProvider shared FieldStore accessor

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 5: Flag + mode setting

**Files:**
- Modify: `swift/packages/CarrierWaveData/Sources/CarrierWaveData/Utilities/ExperimentalFeature.swift`
- Create: `swift/packages/CarrierWaveData/Sources/CarrierWaveData/RustStore/QSOReadSource.swift` (mode enum lives here; read source added in Task 7)

- [ ] **Step 1: Add the hidden experiment case**

In `ExperimentalFeature`: add `case rustStoreQSO` to the enum; add its `displayName` ("QSO Rust Store"), its maturity (`.alpha`), and ensure `isHiddenByDefault` returns `true` for it (follow the exact pattern the other hidden cases use — e.g. `queryRunner`). Add a `case rustStoreQSO:` branch everywhere the compiler now requires exhaustiveness.

- [ ] **Step 2: Define the mode enum** (create `QSOReadSource.swift` with just the enum for now)

```swift
import Foundation

/// Rollout state for serving QSO reads from the Rust store. Stored in
/// `@AppStorage("cwStoreQSOMode")`. SwiftData is always the system of record.
public enum CwStoreQSOMode: String, CaseIterable, Sendable {
    case off      // today's behavior; mirror not observing
    case shadow   // mirror dual-writes; reads from SwiftData + compared to Rust
    case on       // mirror dual-writes; reads served from Rust

    public static let appStorageKey = "cwStoreQSOMode"
}
```

- [ ] **Step 3: Build the package**

Run: `cd swift/packages/CarrierWaveData && swift build 2>&1 | grep -iE "error:|Compiling|Build complete" | tail -5`
Expected: builds (all `switch` statements exhaustive).

- [ ] **Step 4: Commit**

```bash
git add swift/packages/CarrierWaveData/Sources/CarrierWaveData/Utilities/ExperimentalFeature.swift \
        swift/packages/CarrierWaveData/Sources/CarrierWaveData/RustStore/QSOReadSource.swift
git commit -m "Phase 4: rustStoreQSO experiment + CwStoreQSOMode

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 6: `CwStoreMirrorActor` — serial dual-write

**Files:**
- Create: `swift/ios/CarrierWave/Services/RustStore/CwStoreMirrorActor.swift`
- Test: `swift/ios/CarrierWaveTests/RustStore/CwStoreMirrorActorTests.swift`

A serial actor that applies QSO upserts/deletes to the Rust store off the main thread, reusing the importer's `SwiftDataStoreImporter.project(_:)`. Inputs are value types (`FfiQso`, id strings) so no `@Model` crosses the actor boundary.

- [ ] **Step 1: Write the failing test**

```swift
import CarrierWaveCore
import XCTest
@testable import CarrierWave
@testable import CarrierWaveData

final class CwStoreMirrorActorTests: XCTestCase {
    func testUpsertThenDeleteAppliesToStore() async throws {
        let store = try FieldStore.openInMemory(key: "test")
        let actor = CwStoreMirrorActor(store: store)
        let qso = FfiQso.fixtureMinimal(id: "33333333-3333-3333-3333-333333333333")

        await actor.applyUpserts([qso])
        await actor.drain()
        XCTAssertEqual(try store.qsoCount(), 1)

        await actor.applyDeletes(["33333333-3333-3333-3333-333333333333"])
        await actor.drain()
        XCTAssertEqual(try store.qsoCount(), 0)
    }
}
```

> Note: `FfiQso.fixtureMinimal(id:)` — if no such helper exists, build a minimal `FfiQso` inline using the fields the round-trip tests in `CarrierWaveData` already use; do not invent fields. Confirm field names against `CwFfi+Generated.swift`'s `FfiQso`.

- [ ] **Step 2: Run it to confirm it fails**

Run: `cd swift/ios && xcodebuild -project CarrierWave.xcodeproj -scheme CarrierWave -destination "platform=iOS Simulator,id=$SIM" -only-testing:CarrierWaveTests/CwStoreMirrorActorTests test 2>&1 | grep -iE "error:|TEST FAILED|cannot find" | head`
(`SIM` = an available iPhone simulator UDID from `xcrun simctl list devices available`.)
Expected: FAIL — `cannot find 'CwStoreMirrorActor'`.

- [ ] **Step 3: Implement the actor**

```swift
import CarrierWaveCore
import Foundation

/// Serializes QSO dual-writes into the Rust store off the main thread. Accepts
/// only value types so no @Model crosses the boundary. `drain()` is a barrier the
/// read path awaits in `.on` mode so reads never precede pending writes.
actor CwStoreMirrorActor {
    private let store: FieldStore

    init(store: FieldStore) {
        self.store = store
    }

    func applyUpserts(_ qsos: [FfiQso]) {
        for qso in qsos {
            try? store.upsertQso(qso: qso)
        }
    }

    func applyDeletes(_ ids: [String]) {
        for id in ids {
            try? store.deleteQso(id: id)
        }
    }

    /// Barrier: returns once all previously-enqueued work has run. Because this is
    /// an actor and the calls above are non-reentrant, an empty awaited call
    /// flushes the serial queue.
    func drain() {}
}
```

> Note: `try?` swallows per-row failures intentionally — a mirror write must never crash the app or block SwiftData. Failures are surfaced via parity mismatch, not exceptions. (If a logging surface for the cutover is wanted, route through an existing in-app log, never `os_log`.)

- [ ] **Step 4: Run the test to confirm it passes**

Run: same as Step 2.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add swift/ios/CarrierWave/Services/RustStore/CwStoreMirrorActor.swift \
        swift/ios/CarrierWaveTests/RustStore/CwStoreMirrorActorTests.swift
git commit -m "Phase 4: CwStoreMirrorActor serial QSO dual-write

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 7: `QSOReadSource` (count) + parity probe

**Files:**
- Modify: `swift/packages/CarrierWaveData/Sources/CarrierWaveData/RustStore/QSOReadSource.swift`
- Create: `swift/packages/CarrierWaveData/Sources/CarrierWaveData/RustStore/QSOParityProbe.swift`
- Test: `swift/packages/CarrierWaveData/Tests/CarrierWaveDataTests/RustStore/QSOReadSourceTests.swift`

Count only this slice. SwiftData count = `context.fetchCount(FetchDescriptor<QSO>())` (raw total — matches what the verbatim mirror stores). Rust count = `store.qsoCount()`.

- [ ] **Step 1: Write the failing test**

```swift
import CarrierWaveCore
import SwiftData
import XCTest
@testable import CarrierWaveData

@MainActor
final class QSOReadSourceTests: XCTestCase {
    func testRustCountMatchesSwiftDataAfterMirroredUpsert() async throws {
        let container = try ModelContainer(
            for: Schema([QSO.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        context.insert(QSO.testFixture(callsign: "W6JY"))
        try context.save()

        let store = try FieldStore.openInMemory(key: "test")
        try store.upsertQso(qso: SwiftDataStoreImporter.project(QSO.testFixture(callsign: "W6JY")))

        let swiftData = SwiftDataQSOReadSource(context: context)
        let rust = RustQSOReadSource(store: store)
        let sdCount = try await swiftData.count()
        let rustCount = try await rust.count()
        XCTAssertEqual(sdCount, 1)
        XCTAssertEqual(rustCount, 1)

        let probe = QSOParityProbe()
        let result = probe.compareCounts(swiftData: sdCount, rust: rustCount)
        XCTAssertTrue(result.matches)
    }
}
```

> Note: use whatever in-memory QSO fixture the existing CarrierWaveData tests use (e.g. a `QSO.testFixture`/`QSO.testQSO` helper). Match the existing helper; don't invent one. The same QSO value is inserted into SwiftData and projected into Rust so both counts are 1.

- [ ] **Step 2: Run it to confirm it fails**

Run: `cd swift/packages/CarrierWaveData && swift test --filter QSOReadSourceTests 2>&1 | tail -20`
Expected: FAIL — missing types.

- [ ] **Step 3: Implement the read source + probe**

Append to `QSOReadSource.swift`:

```swift
import CarrierWaveCore
import SwiftData

public protocol QSOReadSource: Sendable {
    func count() async throws -> Int
}

public struct SwiftDataQSOReadSource: QSOReadSource {
    private let context: ModelContext
    public init(context: ModelContext) { self.context = context }
    public func count() async throws -> Int {
        try context.fetchCount(FetchDescriptor<QSO>())
    }
}

public struct RustQSOReadSource: QSOReadSource {
    private let store: FieldStore
    public init(store: FieldStore) { self.store = store }
    public func count() async throws -> Int {
        Int(try store.qsoCount())
    }
}
```

Create `QSOParityProbe.swift`:

```swift
import Foundation

/// Compares SwiftData (authoritative) against the Rust mirror. This slice covers
/// the total-count invariant; richer field/order checks arrive with the list
/// migration (sub-project C).
public struct QSOParityProbe: Sendable {
    public init() {}

    public struct CountResult: Sendable, Equatable {
        public let swiftData: Int
        public let rust: Int
        public var matches: Bool { swiftData == rust }
    }

    public func compareCounts(swiftData: Int, rust: Int) -> CountResult {
        CountResult(swiftData: swiftData, rust: rust)
    }
}
```

> Note: `context.fetchCount` is `@MainActor`-bound when the context is the main context; the test class is `@MainActor`. Keep `SwiftDataQSOReadSource` usable from the main actor.

- [ ] **Step 4: Run the test to confirm it passes**

Run: `cd swift/packages/CarrierWaveData && swift test --filter QSOReadSourceTests 2>&1 | tail -20`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add swift/packages/CarrierWaveData/Sources/CarrierWaveData/RustStore/QSOReadSource.swift \
        swift/packages/CarrierWaveData/Sources/CarrierWaveData/RustStore/QSOParityProbe.swift \
        swift/packages/CarrierWaveData/Tests/CarrierWaveDataTests/RustStore/QSOReadSourceTests.swift
git commit -m "Phase 4: QSOReadSource (count) + QSOParityProbe

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 8: `CwStoreMirror` — didSave/willSave observer

**Files:**
- Create: `swift/ios/CarrierWave/Services/RustStore/CwStoreMirror.swift`
- Test: `swift/ios/CarrierWaveTests/RustStore/CwStoreMirrorTests.swift`

Observes `ModelContext` save notifications (`object: nil`), filters to QSO, projects inserts/updates → `FfiQso` upserts, captures delete ids in `willSave`, and forwards to `CwStoreMirrorActor`. Starts/stops based on mode.

- [ ] **Step 1: Write the failing integration test**

```swift
import CarrierWaveCore
import SwiftData
import XCTest
@testable import CarrierWave
@testable import CarrierWaveData

@MainActor
final class CwStoreMirrorTests: XCTestCase {
    func testSaveInsertAndDeleteMirrorToRust() async throws {
        let container = try ModelContainer(
            for: Schema([QSO.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let store = try FieldStore.openInMemory(key: "test")
        let mirror = CwStoreMirror(store: store)
        mirror.start()

        let qso = QSO.testFixture(callsign: "W6JY")
        context.insert(qso)
        try context.save()
        await mirror.drain()
        XCTAssertEqual(try store.qsoCount(), 1)

        context.delete(qso)
        try context.save()
        await mirror.drain()
        XCTAssertEqual(try store.qsoCount(), 0)

        mirror.stop()
    }
}
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `cd swift/ios && xcodebuild ... -only-testing:CarrierWaveTests/CwStoreMirrorTests test 2>&1 | grep -iE "error:|cannot find|TEST FAILED" | head`
Expected: FAIL — `cannot find 'CwStoreMirror'`.

- [ ] **Step 3: Implement the observer**

```swift
import CarrierWaveCore
import CarrierWaveData
import Foundation
import SwiftData

/// Dual-writes QSO changes into the Rust store on every ModelContext save.
/// SwiftData remains the system of record; this keeps the Rust mirror fresh.
@MainActor
final class CwStoreMirror {
    private let mirrorActor: CwStoreMirrorActor
    private var willSaveObserver: NSObjectProtocol?
    private var didSaveObserver: NSObjectProtocol?
    /// PersistentIdentifier → QSO.id captured in willSave for rows about to delete.
    private var pendingDeleteIDs: [PersistentIdentifier: String] = [:]

    init(store: FieldStore) {
        self.mirrorActor = CwStoreMirrorActor(store: store)
    }

    func start() {
        guard didSaveObserver == nil else { return }
        willSaveObserver = NotificationCenter.default.addObserver(
            forName: ModelContext.willSave, object: nil, queue: nil
        ) { [weak self] note in
            MainActor.assumeIsolated { self?.captureDeletes(note) }
        }
        didSaveObserver = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: nil, queue: nil
        ) { [weak self] note in
            MainActor.assumeIsolated { self?.handleDidSave(note) }
        }
    }

    func stop() {
        [willSaveObserver, didSaveObserver].compactMap { $0 }.forEach(NotificationCenter.default.removeObserver)
        willSaveObserver = nil
        didSaveObserver = nil
        pendingDeleteIDs.removeAll()
    }

    func drain() async { await mirrorActor.drain() }

    private func captureDeletes(_ note: Notification) {
        guard let context = note.object as? ModelContext else { return }
        for case let qso as QSO in context.deletedModelsArray where qso is QSO {
            pendingDeleteIDs[qso.persistentModelID] = SwiftDataStoreImporter.uuid(qso.id)
        }
    }

    private func handleDidSave(_ note: Notification) {
        let info = note.userInfo ?? [:]
        let inserted = (info[ModelContext.NotificationKey.insertedIdentifiers.rawValue] as? [PersistentIdentifier]) ?? []
        let updated  = (info[ModelContext.NotificationKey.updatedIdentifiers.rawValue]  as? [PersistentIdentifier]) ?? []
        let deleted  = (info[ModelContext.NotificationKey.deletedIdentifiers.rawValue]  as? [PersistentIdentifier]) ?? []

        guard let context = note.object as? ModelContext else { return }
        let changed = inserted + updated
        let upserts: [FfiQso] = changed.compactMap { pid in
            guard let qso = context.registeredModel(for: pid) as QSO? else { return nil }
            return SwiftDataStoreImporter.project(qso)
        }
        let deleteIDs: [String] = deleted.compactMap { pendingDeleteIDs.removeValue(forKey: $0) }

        Task { [mirrorActor] in
            if !upserts.isEmpty { await mirrorActor.applyUpserts(upserts) }
            if !deleteIDs.isEmpty { await mirrorActor.applyDeletes(deleteIDs) }
        }
    }
}
```

> **Verification required while implementing:** the exact SwiftData notification API for inserted/updated/deleted identifiers varies by OS version. Confirm against `CloudSyncJournalEngine`'s existing `ModelContext.didSave` observer (it already extracts changed objects) and copy its exact key/access pattern (`ModelContext.NotificationKey`, `deletedModelsArray`, `registeredModel(for:)` or its equivalent). Do not invent API names — mirror the working code already in the repo. If the journal engine reads objects a different way, use that way.

- [ ] **Step 4: Run the test to confirm it passes**

Run: same as Step 2 (without the failure grep).
Expected: PASS — count goes 0→1→0.

- [ ] **Step 5: Commit**

```bash
git add swift/ios/CarrierWave/Services/RustStore/CwStoreMirror.swift \
        swift/ios/CarrierWaveTests/RustStore/CwStoreMirrorTests.swift
git commit -m "Phase 4: CwStoreMirror didSave/willSave QSO dual-write observer

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 9: Wire lifecycle + Data Migration UI

**Files:**
- Modify: `swift/ios/CarrierWave/CarrierWaveApp.swift`
- Modify: `swift/ios/CarrierWave/Views/Settings/ExperimentsView.swift`

- [ ] **Step 1: Own a `CwStoreMirror` and react to mode**

In `CarrierWaveApp`, after the container is created: hold a `@State`/stored `CwStoreMirror?`. On launch and whenever `@AppStorage(CwStoreQSOMode.appStorageKey)` is `.shadow` or `.on`, run the enable sequence (spec §write-path): **(1)** create the mirror from `try await CwStoreProvider.shared.store()` and `start()` it; **(2)** run the idempotent reconcile import via the existing `CwStoreImportCoordinator.appGroup(version:).runIfNeeded(from:)`. On `.off`, `stop()` and release the mirror. Gate the whole control behind `ExperimentalFeature.isEnabled(.rustStoreQSO)`.

- [ ] **Step 2: Add the mode picker + parity action to Data Migration**

In `ExperimentsView`'s Data Migration section, when `ExperimentalFeature.isEnabled(.rustStoreQSO)`: add a `Picker` bound to `@AppStorage(CwStoreQSOMode.appStorageKey)` with off/shadow/on, and a "Run QSO parity check" button. The button:

```swift
private func runQSOParityCheck() {
    parityStatus = "Checking…"
    let container = modelContext.container
    Task.detached {
        let message: String
        do {
            let store = try await CwStoreProvider.shared.store()
            let count = try await MainActor.run {
                try ModelContext(container).fetchCount(FetchDescriptor<QSO>())
            }
            let rust = Int(try store.qsoCount())
            let result = QSOParityProbe().compareCounts(swiftData: count, rust: rust)
            message = result.matches
                ? "QSO parity OK: \(count) rows."
                : "QSO parity MISMATCH: SwiftData \(result.swiftData) ≠ Rust \(result.rust)."
        } catch {
            message = "Parity check failed: \(error.localizedDescription)"
        }
        await MainActor.run { parityStatus = message }
    }
}
```

> Note: match `ExperimentsView`'s existing detached-task + `@State status` pattern (used by the importer row). Reuse its style; add `@State private var parityStatus: String?`.

- [ ] **Step 3: Build for device**

Run: `cd swift/ios && xcodebuild -project CarrierWave.xcodeproj -scheme CarrierWave -destination 'generic/platform=iOS' build 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add swift/ios/CarrierWave/CarrierWaveApp.swift swift/ios/CarrierWave/Views/Settings/ExperimentsView.swift
git commit -m "Phase 4: wire CwStoreMirror lifecycle + QSO parity check UI

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 10: Device verification

**Files:** none (manual on-device validation).

- [ ] **Step 1: Deploy to device**

Run: `cd swift/ios && xcodebuild ... -destination 'generic/platform=iOS' build`, then `xcrun devicectl device install app --device theseus <CarrierWave.app>` and `... process launch ... com.jsvana.FullDuplex`.

- [ ] **Step 2: Enable + verify parity**

On device: enable the `QSO Rust Store` experiment, set mode to `shadow`. Tap **Run QSO parity check**.
Expected: `QSO parity OK: N rows.` (N = your QSO count). If it mismatches, the mirror reconcile import didn't complete — re-check Task 9 Step 1 sequencing.

- [ ] **Step 3: Live-write parity**

Log a QSO (or delete one), then re-run the parity check.
Expected: still `QSO parity OK` with the count adjusted — confirms `CwStoreMirror` captured the live save.

- [ ] **Step 4: Confirm no crash**

Run: `~/.claude/skills/xcode-build/scripts/xc crashes 2>&1 | grep CarrierWave-2026 | tail -3`
Expected: no new crash newer than the deploy.

- [ ] **Step 5: Flip `off` (rollback)**

Set mode to `off`; confirm the app behaves exactly as before (mirror stops; SwiftData untouched).

---

## Self-review notes

- **Spec coverage (A):** `delete_qso`/notify (Tasks 1–2), shared accessor (Task 4), mirror dual-write incl. deletes via willSave capture (Tasks 6, 8), flag/mode (Task 5), `QSOReadSource`+probe count (Task 7), enable sequencing + UI (Task 9), device parity incl. live-write & rollback (Task 10). Logbook list, DSL port, write-cutover are explicitly **out** (sub-projects B/C).
- **Type consistency:** `CwStoreMirrorActor.drain()`, `CwStoreMirror.drain()`, `QSOParityProbe.compareCounts(swiftData:rust:)`, `CwStoreQSOMode.appStorageKey`, `CwStoreProvider.shared.store()` used consistently across tasks.
- **Known verify-on-implement points (flagged inline, not placeholders):** exact SwiftData save-notification key API (mirror `CloudSyncJournalEngine`), the existing QSO test-fixture helper name, and `FfiQso` field names (check `CwFfi+Generated.swift`). These are "match existing code" instructions, not gaps.

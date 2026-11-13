import CarrierWaveCore
import SwiftData
import XCTest
@testable import CarrierWave
@testable import CarrierWaveData

@MainActor
final class CwStoreMirrorTests: XCTestCase {
    func testSaveInsertAndDeleteMirrorToRust() async throws {
        // Use QSO + ServicePresence so the schema has the inverse relationship
        // that QSO.servicePresence needs, otherwise SwiftData may not track changes.
        let container = try ModelContainer(
            for: Schema([QSO.self, ServicePresence.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let store = try FieldStore.openInMemory(key: "test")
        let mirror = CwStoreMirror(store: store)
        mirror.start()

        let qso = QSOFactory.generate(count: 1)[0]
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

    /// Regression: the observer fires on the executor of whatever ModelContext
    /// saves. A save on a BACKGROUND context (off the main actor) previously
    /// crashed because the handler used `MainActor.assumeIsolated`. The
    /// thread-agnostic mirror must capture the change on the saving thread.
    func testBackgroundContextSaveMirrorsWithoutAssumingMainActor() async throws {
        let container = try ModelContainer(
            for: Schema([QSO.self, ServicePresence.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let store = try FieldStore.openInMemory(key: "test")
        let mirror = CwStoreMirror(store: store)
        mirror.start()

        try await Task.detached {
            let bgContext = ModelContext(container)
            bgContext.insert(QSO(
                callsign: "W6JY",
                band: "20m",
                mode: "CW",
                timestamp: Date(),
                myCallsign: "W6JY",
                importSource: .logger
            ))
            try bgContext.save()
        }.value

        await mirror.drain()
        XCTAssertEqual(try store.qsoCount(), 1)

        mirror.stop()
    }

    /// ServicePresence insert and delete on the main context are mirrored to
    /// the Rust store so synced:/pending: query fields stay fresh.
    func testServicePresenceInsertAndDeleteMirrorToRust() async throws {
        let container = try ModelContainer(
            for: Schema([QSO.self, ServicePresence.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let store = try FieldStore.openInMemory(key: "test-sp-main")
        let mirror = CwStoreMirror(store: store)
        mirror.start()
        defer { mirror.stop() }

        let qso = QSOFactory.generate(count: 1)[0]
        let sp = ServicePresence(serviceType: .qrz, isPresent: true, qso: qso)
        context.insert(qso)
        context.insert(sp)
        try context.save()
        await mirror.drain()
        XCTAssertEqual(try store.servicePresenceCount(), 1)

        context.delete(sp)
        try context.save()
        await mirror.drain()
        XCTAssertEqual(try store.servicePresenceCount(), 0)
    }

    /// Regression: ServicePresence save on a background context must NOT crash.
    /// Mirrors the QSO background-context test for ServicePresence.
    func testBackgroundContextServicePresenceMirrorsWithoutCrash() async throws {
        let container = try ModelContainer(
            for: Schema([QSO.self, ServicePresence.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let store = try FieldStore.openInMemory(key: "test-sp-bg")
        let mirror = CwStoreMirror(store: store)
        mirror.start()
        defer { mirror.stop() }

        try await Task.detached {
            let bgContext = ModelContext(container)
            let qso = QSO(
                callsign: "W6JY",
                band: "20m",
                mode: "CW",
                timestamp: Date(),
                myCallsign: "W6JY",
                importSource: .logger
            )
            let sp = ServicePresence(serviceType: .qrz, isPresent: true, qso: qso)
            bgContext.insert(qso)
            bgContext.insert(sp)
            try bgContext.save()
        }.value

        await mirror.drain()
        XCTAssertEqual(try store.servicePresenceCount(), 1)
    }
}

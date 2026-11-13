import CarrierWaveCore
import SwiftData
import XCTest
@testable import CarrierWave
@testable import CarrierWaveData

@MainActor
final class QSOWriteSinkTests: XCTestCase {
    // MARK: Internal

    /// While a seam write is in flight, the mirror must NOT capture QSO changes —
    /// otherwise the seam's SwiftData save would echo back into cw-store.
    func testSeamWriteSuppressesMirrorCapture() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let store = try FieldStore.openInMemory(key: "suppress")
        let mirror = CwStoreMirror(store: store)
        mirror.start()
        defer { mirror.stop() }

        mirror.beginSeamWrite(for: context)
        context.insert(QSOFactory.generate(count: 1)[0])
        try context.save()
        mirror.endSeamWrite(for: context)
        await mirror.drain()

        XCTAssertEqual(try store.qsoCount(), 0, "capture must be skipped during a seam write")
    }

    func testWriteLogCapsAtFifty() {
        let log = CwStoreWriteLog()
        for index in 0 ..< 60 {
            log.record("entry \(index)")
        }
        XCTAssertEqual(log.entries.count, 50)
        XCTAssertTrue(log.entries.last?.contains("entry 59") ?? false)
        XCTAssertFalse(log.entries.first?.contains("entry 0") ?? true)
    }

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

    /// `on` mode: upsertBatch writes both new QSOs to the cw-store base set, suppressed.
    func testOnModeUpsertBatchWritesAll() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let store = try FieldStore.openInMemory(key: "on-upsert-batch")
        let mirror = CwStoreMirror(store: store)
        mirror.start()
        defer { mirror.stop() }

        let qsos = QSOFactory.generate(count: 2)
        for qso in qsos {
            context.insert(qso)
        }
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
        for qso in qsos {
            context.insert(qso)
        }
        let sink = QSOWriteSink(store: store, mirror: mirror, modeProvider: { .on })
        try sink.upsertBatch(qsos, in: context)
        XCTAssertEqual(try store.qsoCount(), 2)

        try sink.deleteBatch(qsos, in: context)
        await mirror.drain()
        XCTAssertEqual(try store.qsoCount(), 0, "deleted from cw-store")
        var countDescriptor = FetchDescriptor<QSO>()
        countDescriptor.fetchLimit = 10
        XCTAssertEqual(try context.fetchCount(countDescriptor), 0, "deleted from SwiftData")
    }

    /// The mirror now covers non-QSO entities: a saved `LoggingSession` upserts into
    /// cw-store, and a delete removes it (W3 follow-on — entity write coverage).
    func testMirrorsLoggingSessionUpsertAndDelete() async throws {
        let container = try ModelContainer(
            for: Schema([LoggingSession.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let store = try FieldStore.openInMemory(key: "mirror-session")
        let mirror = CwStoreMirror(store: store)
        mirror.start()
        defer { mirror.stop() }

        let session = LoggingSession(myCallsign: "N0TEST")
        context.insert(session)
        try context.save()
        await mirror.drain()
        XCTAssertEqual(try store.loggingSessionCount(), 1, "session upsert mirrored to cw-store")

        context.delete(session)
        try context.save()
        await mirror.drain()
        XCTAssertEqual(try store.loggingSessionCount(), 0, "session delete mirrored to cw-store")
    }

    // MARK: Private

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema([QSO.self, ServicePresence.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }
}

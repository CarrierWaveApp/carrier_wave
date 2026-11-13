import CarrierWaveCore
import SwiftData
import Testing
import XCTest
@testable import CarrierWaveData

// MARK: - LoggingSessionReadSourceTests

@MainActor
final class LoggingSessionReadSourceTests: XCTestCase {
    func testRustCountMatchesSwiftDataAfterMirroredUpsert() async throws {
        let container = try ModelContainer(
            for: Schema([LoggingSession.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let session = LoggingSession(myCallsign: "W6JY", startedAt: Date(timeIntervalSince1970: 1_000))
        context.insert(session)
        try context.save()

        let store = try FieldStore.openInMemory(key: "logging-session-test")
        try store.upsertLoggingSession(item: SwiftDataStoreImporter.project(session))

        let swiftData = SwiftDataLoggingSessionReadSource(context: context)
        let rust = RustLoggingSessionReadSource(store: store)
        let sdCount = try await swiftData.count()
        let rustCount = try await rust.count()
        XCTAssertEqual(sdCount, 1)
        XCTAssertEqual(rustCount, 1)

        let result = StoreCountParity().compare(entity: "LoggingSession", swiftData: sdCount, rust: rustCount)
        XCTAssertTrue(result.matches)
    }

    func testCountParityHoldsAcrossMultipleSessions() async throws {
        let container = try ModelContainer(
            for: Schema([LoggingSession.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let store = try FieldStore.openInMemory(key: "logging-session-multi")

        for index in 0 ..< 5 {
            let session = LoggingSession(
                myCallsign: "W6JY",
                startedAt: Date(timeIntervalSince1970: TimeInterval(1_000 + index))
            )
            context.insert(session)
            try store.upsertLoggingSession(item: SwiftDataStoreImporter.project(session))
        }
        try context.save()

        let swiftData = SwiftDataLoggingSessionReadSource(context: context)
        let rust = RustLoggingSessionReadSource(store: store)
        let sdCount = try await swiftData.count()
        let rustCount = try await rust.count()
        let result = StoreCountParity().compare(entity: "LoggingSession", swiftData: sdCount, rust: rustCount)
        XCTAssertEqual(result.swiftData, 5)
        XCTAssertTrue(result.matches)
    }

    func testFieldAndOrderParityAfterMirroredUpsert() async throws {
        let container = try ModelContainer(
            for: Schema([LoggingSession.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext

        // Two sessions, with a spread of fields set across the solar / weather /
        // contest / TOTA / flag groups so the round-trip exercises real columns.
        let pota = LoggingSession(myCallsign: "W6JY", startedAt: Date(timeIntervalSince1970: 1_700_000_000))
        pota.parkReference = "US-0001"
        pota.frequency = 14.074
        pota.mode = "FT8"
        pota.power = 5
        pota.qsoCount = 42
        pota.notes = "Great run"
        pota.solarFlux = 142.5
        pota.weatherTemperatureF = 68.0
        pota.isRove = true
        pota.qrpActivation = true

        let contest = LoggingSession(myCallsign: "W6JY", startedAt: Date(timeIntervalSince1970: 1_700_001_000))
        contest.contestId = "cqww"
        contest.contestCategory = "SOAB"
        contest.totaCategoryRawValue = "fixed"
        contest.personalEffortFactor = 3

        context.insert(pota)
        context.insert(contest)
        try context.save()

        let store = try FieldStore.openInMemory(key: "logging-session-fields")
        try store.upsertLoggingSession(item: SwiftDataStoreImporter.project(pota))
        try store.upsertLoggingSession(item: SwiftDataStoreImporter.project(contest))

        let swiftData = SwiftDataLoggingSessionReadSource(context: context)
        let rust = RustLoggingSessionReadSource(store: store)

        let sdAll = try await swiftData.all()
        let rustAll = try await rust.all()
        XCTAssertEqual(sdAll.count, 2)
        XCTAssertEqual(sdAll, rustAll)
    }

    func testFieldParityHoldsAfterUpdate() async throws {
        let container = try ModelContainer(
            for: Schema([LoggingSession.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let store = try FieldStore.openInMemory(key: "logging-session-field-update")

        let session = LoggingSession(myCallsign: "W6JY", startedAt: Date(timeIntervalSince1970: 1_700_000_000))
        context.insert(session)
        try context.save()
        try store.upsertLoggingSession(item: SwiftDataStoreImporter.project(session))

        session.endedAt = Date(timeIntervalSince1970: 1_700_003_600)
        session.qsoCount = 17
        session.customTitle = "Closed out"
        try context.save()
        try store.upsertLoggingSession(item: SwiftDataStoreImporter.project(session))

        let swiftData = SwiftDataLoggingSessionReadSource(context: context)
        let rust = RustLoggingSessionReadSource(store: store)
        let sdAll = try await swiftData.all()
        let rustAll = try await rust.all()
        XCTAssertEqual(sdAll.count, 1)
        XCTAssertEqual(sdAll, rustAll)
        XCTAssertEqual(rustAll.first?.qsoCount, 17)
        XCTAssertEqual(rustAll.first?.customTitle, "Closed out")
    }
}

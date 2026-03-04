import CarrierWaveData
import SwiftData
import XCTest
@testable import CarrierWave

/// Tests for KIndexRepairService.
///
/// Validates that corrupted K-index data (always 0) from before the HamQSL
/// XML whitespace fix (Feb 14, 2026) is cleared, while preserving valid
/// SFI/sunspot data and records after the fix date.
@MainActor
final class KIndexRepairServiceTests: XCTestCase {
    // MARK: Internal

    override func setUp() async throws {
        try await super.setUp()
        let schema = Schema(CarrierWaveSchema.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        try await super.tearDown()
    }

    // MARK: - Session Repair

    /// Sessions with kIndex=0 before cutoff get kIndex and propagationRating cleared.
    func testRepairsSessionsWithZeroKIndexBeforeCutoff() async throws {
        let session = LoggingSession(
            myCallsign: "N0TEST",
            startedAt: dateBeforeCutoff,
            mode: "CW"
        )
        session.solarKIndex = 0
        session.solarFlux = 150
        session.solarSunspots = 80
        session.solarPropagationRating = "Excellent"
        context.insert(session)
        try context.save()

        let service = KIndexRepairService(container: container)
        let result = try await service.repair()

        XCTAssertEqual(result.sessionsRepaired, 1)

        // Re-fetch to verify
        let descriptor = FetchDescriptor<LoggingSession>()
        let fetched = try context.fetch(descriptor)
        let repaired = try XCTUnwrap(fetched.first)
        XCTAssertNil(repaired.solarKIndex, "K-index should be cleared")
        XCTAssertNil(repaired.solarPropagationRating, "Propagation rating should be cleared")
        XCTAssertEqual(repaired.solarFlux, 150, "SFI should be preserved")
        XCTAssertEqual(repaired.solarSunspots, 80, "Sunspots should be preserved")
    }

    /// Sessions with kIndex=0 after cutoff are NOT touched.
    func testDoesNotRepairSessionsAfterCutoff() async throws {
        let session = LoggingSession(
            myCallsign: "N0TEST",
            startedAt: dateAfterCutoff,
            mode: "CW"
        )
        session.solarKIndex = 0
        session.solarPropagationRating = "Excellent"
        context.insert(session)
        try context.save()

        let service = KIndexRepairService(container: container)
        let result = try await service.repair()

        XCTAssertEqual(result.sessionsRepaired, 0)

        let descriptor = FetchDescriptor<LoggingSession>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.first?.solarKIndex, 0, "K-index should remain 0 (after cutoff)")
    }

    /// Sessions with kIndex != 0 are NOT touched.
    func testDoesNotRepairSessionsWithNonZeroKIndex() async throws {
        let session = LoggingSession(
            myCallsign: "N0TEST",
            startedAt: dateBeforeCutoff,
            mode: "CW"
        )
        session.solarKIndex = 3.5
        session.solarPropagationRating = "Fair"
        context.insert(session)
        try context.save()

        let service = KIndexRepairService(container: container)
        let result = try await service.repair()

        XCTAssertEqual(result.sessionsRepaired, 0)

        let descriptor = FetchDescriptor<LoggingSession>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.first?.solarKIndex, 3.5, "K-index should be untouched")
    }

    // MARK: - Metadata Repair

    /// Metadata with kIndex=0 before cutoff gets kIndex and propagationRating cleared.
    func testRepairsMetadataWithZeroKIndexBeforeCutoff() async throws {
        let meta = ActivationMetadata(
            parkReference: "US-0001",
            date: dateBeforeCutoff
        )
        meta.solarKIndex = 0
        meta.solarFlux = 120
        meta.solarSunspots = 60
        meta.solarPropagationRating = "Excellent"
        context.insert(meta)
        try context.save()

        let service = KIndexRepairService(container: container)
        let result = try await service.repair()

        XCTAssertEqual(result.metadataRepaired, 1)

        let descriptor = FetchDescriptor<ActivationMetadata>()
        let fetched = try context.fetch(descriptor)
        let repaired = try XCTUnwrap(fetched.first)
        XCTAssertNil(repaired.solarKIndex, "K-index should be cleared")
        XCTAssertNil(repaired.solarPropagationRating, "Propagation rating should be cleared")
        XCTAssertEqual(repaired.solarFlux, 120, "SFI should be preserved")
        XCTAssertEqual(repaired.solarSunspots, 60, "Sunspots should be preserved")
    }

    /// Metadata with kIndex=0 after cutoff is NOT touched.
    func testDoesNotRepairMetadataAfterCutoff() async throws {
        let meta = ActivationMetadata(
            parkReference: "US-0001",
            date: dateAfterCutoff
        )
        meta.solarKIndex = 0
        meta.solarPropagationRating = "Excellent"
        context.insert(meta)
        try context.save()

        let service = KIndexRepairService(container: container)
        let result = try await service.repair()

        XCTAssertEqual(result.metadataRepaired, 0)
    }

    /// Empty store produces zero repairs.
    func testEmptyStoreReturnsZero() async throws {
        let service = KIndexRepairService(container: container)
        let result = try await service.repair()

        XCTAssertEqual(result.sessionsRepaired, 0)
        XCTAssertEqual(result.metadataRepaired, 0)
    }

    // MARK: Private

    private var container: ModelContainer!
    private var context: ModelContext!

    /// Jan 1, 2026 — well before the cutoff
    private let dateBeforeCutoff: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: 2_026, month: 1, day: 1))!
    }()

    /// Feb 16, 2026 — after the cutoff
    private let dateAfterCutoff: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: 2_026, month: 2, day: 16))!
    }()
}

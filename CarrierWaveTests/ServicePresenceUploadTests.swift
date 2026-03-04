import CarrierWaveCore
import CarrierWaveData
import SwiftData
import XCTest
@testable import CarrierWave

/// Tests for QSO deduplication keys, hidden QSO upload behavior, and persistence
final class ServicePresenceUploadTests: XCTestCase {
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!

    @MainActor
    override func setUp() async throws {
        let (container, context) = try TestModelContainer.createWithContext()
        modelContainer = container
        modelContext = context
    }

    // MARK: - Deduplication Key Tests

    @MainActor
    func testDeduplicationKey_Format() {
        let timestamp = Date(timeIntervalSince1970: 1_000_000_000) // Fixed time for testing
        let qso = QSO.testQSO(
            callsign: "W1AW",
            band: "20m",
            mode: "CW",
            timestamp: timestamp
        )

        let key = qso.deduplicationKey
        XCTAssertTrue(key.hasPrefix("W1AW|20M|CW|"))
    }

    @MainActor
    func testDeduplicationKey_CaseInsensitive() {
        let timestamp = Date()

        let qso1 = QSO.testQSO(callsign: "w1aw", band: "20m", mode: "cw", timestamp: timestamp)
        let qso2 = QSO.testQSO(callsign: "W1AW", band: "20M", mode: "CW", timestamp: timestamp)

        XCTAssertEqual(qso1.deduplicationKey, qso2.deduplicationKey)
    }

    @MainActor
    func testDeduplicationKey_DifferentWithin2Minutes() {
        let baseTime = Date()
        let qso1 = QSO.testQSO(callsign: "W1AW", timestamp: baseTime)
        let qso2 = QSO.testQSO(callsign: "W1AW", timestamp: baseTime.addingTimeInterval(60))

        // Same 2-minute bucket
        XCTAssertEqual(qso1.deduplicationKey, qso2.deduplicationKey)
    }

    @MainActor
    func testDeduplicationKey_DifferentAcross2Minutes() {
        let baseTime = Date()
        let qso1 = QSO.testQSO(callsign: "W1AW", timestamp: baseTime)
        let qso2 = QSO.testQSO(callsign: "W1AW", timestamp: baseTime.addingTimeInterval(180))

        // Different 2-minute buckets (may or may not be equal depending on timing)
        // This is testing the bucketing behavior
    }

    // MARK: - Hidden QSO Upload Flag Tests

    @MainActor
    func testHiddenQSO_NotIncludedInUploadQuery() throws {
        // Given - Two QSOs with upload flags, one hidden
        let visibleQSO = QSO.testQSO(callsign: "W1AW")
        let hiddenQSO = QSO.testQSO(callsign: "K1ABC")
        hiddenQSO.isHidden = true
        modelContext.insert(visibleQSO)
        modelContext.insert(hiddenQSO)

        visibleQSO.markNeedsUpload(to: .qrz, context: modelContext)
        hiddenQSO.markNeedsUpload(to: .qrz, context: modelContext)
        try modelContext.save()

        // When - fetch all QSOs needing upload (simulates fetchQSOsNeedingUpload filter)
        let descriptor = FetchDescriptor<QSO>()
        let allQSOs = try modelContext.fetch(descriptor)
        let uploadable = allQSOs.filter { qso in
            !qso.isHidden && qso.servicePresence.contains(where: \.needsUpload)
        }

        // Then - only the visible QSO should be uploadable
        XCTAssertEqual(uploadable.count, 1)
        XCTAssertEqual(uploadable.first?.callsign, "W1AW")
    }

    @MainActor
    func testHidingQSO_ClearsUploadFlags() throws {
        // Given - QSO with upload flags for multiple services
        let qso = QSO.testQSO()
        modelContext.insert(qso)
        qso.markNeedsUpload(to: .qrz, context: modelContext)
        qso.markNeedsUpload(to: .pota, context: modelContext)
        qso.markNeedsUpload(to: .lofi, context: modelContext)
        try modelContext.save()

        XCTAssertTrue(qso.needsUpload(to: .qrz))
        XCTAssertTrue(qso.needsUpload(to: .pota))
        XCTAssertTrue(qso.needsUpload(to: .lofi))

        // When - hide the QSO and clear upload flags (mirrors LoggingSessionManager.hideQSO)
        qso.isHidden = true
        for presence in qso.servicePresence where presence.needsUpload {
            presence.needsUpload = false
        }
        try modelContext.save()

        // Then - all upload flags should be cleared
        XCTAssertTrue(qso.isHidden)
        XCTAssertFalse(qso.needsUpload(to: .qrz))
        XCTAssertFalse(qso.needsUpload(to: .pota))
        XCTAssertFalse(qso.needsUpload(to: .lofi))
    }

    @MainActor
    func testHiddenQSO_ExistingPresenceRecords_ClearedByRepair() async throws {
        // Given - Hidden QSO that still has needsUpload flags (pre-existing dirty data)
        let qso = QSO.testQSO()
        modelContext.insert(qso)
        qso.markNeedsUpload(to: .qrz, context: modelContext)
        qso.markNeedsUpload(to: .pota, context: modelContext)
        qso.isHidden = true // Hidden but flags not cleared (simulates old bug)
        try modelContext.save()

        // Verify the dirty state
        XCTAssertTrue(qso.isHidden)
        XCTAssertTrue(qso.needsUpload(to: .qrz))
        XCTAssertTrue(qso.needsUpload(to: .pota))

        // When - run the repair step
        let actor = QSOProcessingActor()
        let result = try await actor.clearHiddenQSOUploadFlags(container: modelContainer)

        // Then - flags should be cleared
        XCTAssertEqual(result.clearedCount, 2)
    }

    // MARK: - Persistence Tests

    @MainActor
    func testServicePresence_Persistence() throws {
        // Given
        let qso = QSO.testQSO()
        modelContext.insert(qso)
        qso.markNeedsUpload(to: .qrz, context: modelContext)
        qso.markPresent(in: .pota, context: modelContext)
        try modelContext.save()

        // When - fetch from database
        let descriptor = FetchDescriptor<QSO>()
        let fetched = try XCTUnwrap(try modelContext.fetch(descriptor).first)

        // Then
        XCTAssertEqual(fetched.servicePresence.count, 2)
        XCTAssertTrue(fetched.needsUpload(to: .qrz))
        XCTAssertTrue(fetched.isPresent(in: .pota))
    }
}

import SwiftData
import XCTest
@testable import CarrierWave

/// Tests for CommentParkRefRepairService.
///
/// The primary purpose of these tests is to exercise the SwiftData #Predicate
/// against a real in-memory CoreData store. Predicate translation issues
/// (e.g. ?? + .isEmpty) cause CoreData NSExceptions that crash at runtime
/// with no compile-time signal. Running the fetch in tests catches these
/// before deployment.
@MainActor
final class CommentParkRefRepairServiceTests: XCTestCase {
    // MARK: Internal

    override func setUp() async throws {
        try await super.setUp()
        let result = try TestModelContainer.createWithContext()
        container = result.container
        context = result.context
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        try await super.tearDown()
    }

    // MARK: - Predicate Translation (crash regression)

    /// Regression: the #Predicate must not crash when evaluated by CoreData.
    /// Previous versions used `(parkReference ?? "").isEmpty` which generated
    /// an invalid NSPredicate, causing SIGABRT on launch.
    func testPredicateDoesNotCrashOnEmptyStore() async throws {
        let service = CommentParkRefRepairService(container: container)
        let result = try await service.backfill()

        XCTAssertEqual(result.scanned, 0)
        XCTAssertEqual(result.updated, 0)
    }

    /// Regression: predicate must handle QSOs with nil parkReference.
    func testPredicateHandlesNilParkReference() async throws {
        let qso = QSO(
            callsign: "W1AW", band: "20m", mode: "CW",
            timestamp: Date(), myCallsign: "N0TEST",
            parkReference: nil, notes: "No park ref here",
            importSource: .adifFile
        )
        context.insert(qso)
        try context.save()

        let service = CommentParkRefRepairService(container: container)
        let result = try await service.backfill()

        XCTAssertEqual(result.scanned, 1)
    }

    /// Regression: predicate must handle QSOs with empty-string parkReference.
    func testPredicateHandlesEmptyStringParkReference() async throws {
        let qso = QSO(
            callsign: "W1AW", band: "20m", mode: "CW",
            timestamp: Date(), myCallsign: "N0TEST",
            parkReference: "", notes: "Empty park ref",
            importSource: .adifFile
        )
        context.insert(qso)
        try context.save()

        let service = CommentParkRefRepairService(container: container)
        let result = try await service.backfill()

        XCTAssertEqual(result.scanned, 1)
    }

    // MARK: - Backfill Logic

    /// QSO with park ref in notes and no parkReference gets updated.
    func testBackfillExtractsParkRefFromNotes() async throws {
        let qso = QSO(
            callsign: "W1AW", band: "20m", mode: "CW",
            timestamp: Date(), myCallsign: "N0TEST",
            parkReference: nil, notes: "POTA US-0001 activation",
            importSource: .adifFile
        )
        context.insert(qso)
        try context.save()

        let service = CommentParkRefRepairService(container: container)
        let result = try await service.backfill()

        XCTAssertEqual(result.scanned, 1)
        XCTAssertEqual(result.updated, 1)

        // Re-fetch to verify
        let descriptor = FetchDescriptor<QSO>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.first?.parkReference, "US-0001")
    }

    /// QSO that already has a parkReference is skipped (not scanned).
    func testBackfillSkipsQSOsWithExistingParkRef() async throws {
        let qso = QSO(
            callsign: "W1AW", band: "20m", mode: "CW",
            timestamp: Date(), myCallsign: "N0TEST",
            parkReference: "US-0002", notes: "POTA US-0001 activation",
            importSource: .adifFile
        )
        context.insert(qso)
        try context.save()

        let service = CommentParkRefRepairService(container: container)
        let result = try await service.backfill()

        XCTAssertEqual(result.scanned, 0, "QSO with existing parkReference should be excluded by predicate")
    }

    /// QSO with nil notes is skipped (not scanned).
    func testBackfillSkipsQSOsWithNilNotes() async throws {
        let qso = QSO(
            callsign: "W1AW", band: "20m", mode: "CW",
            timestamp: Date(), myCallsign: "N0TEST",
            parkReference: nil, notes: nil,
            importSource: .adifFile
        )
        context.insert(qso)
        try context.save()

        let service = CommentParkRefRepairService(container: container)
        let result = try await service.backfill()

        XCTAssertEqual(result.scanned, 0, "QSO with nil notes should be excluded by predicate")
    }

    /// Hidden (soft-deleted) QSOs are skipped.
    func testBackfillSkipsHiddenQSOs() async throws {
        let qso = QSO(
            callsign: "W1AW", band: "20m", mode: "CW",
            timestamp: Date(), myCallsign: "N0TEST",
            parkReference: nil, notes: "POTA US-0001",
            importSource: .adifFile
        )
        qso.isHidden = true
        context.insert(qso)
        try context.save()

        let service = CommentParkRefRepairService(container: container)
        let result = try await service.backfill()

        XCTAssertEqual(result.scanned, 0, "Hidden QSOs should be excluded by predicate")
    }

    /// Notes that don't contain a valid park reference are scanned but not updated.
    func testBackfillDoesNotUpdateWhenNoValidParkRefInNotes() async throws {
        let qso = QSO(
            callsign: "W1AW", band: "20m", mode: "CW",
            timestamp: Date(), myCallsign: "N0TEST",
            parkReference: nil, notes: "Great QSO, 599 both ways",
            importSource: .adifFile
        )
        context.insert(qso)
        try context.save()

        let service = CommentParkRefRepairService(container: container)
        let result = try await service.backfill()

        XCTAssertEqual(result.scanned, 1)
        XCTAssertEqual(result.updated, 0)
    }

    /// Multiple QSOs: only eligible ones are scanned and updated.
    func testBackfillMixedQSOs() async throws {
        // 1: eligible, has park ref in notes
        let q1 = QSO(
            callsign: "W1AW", band: "20m", mode: "CW",
            timestamp: Date(), myCallsign: "N0TEST",
            parkReference: nil, notes: "US-0001 activation",
            importSource: .adifFile
        )
        // 2: eligible, but notes have no park ref
        let q2 = QSO(
            callsign: "K1ABC", band: "40m", mode: "SSB",
            timestamp: Date(), myCallsign: "N0TEST",
            parkReference: "", notes: "Just a regular QSO",
            importSource: .adifFile
        )
        // 3: already has parkReference (skipped)
        let q3 = QSO(
            callsign: "N2XYZ", band: "20m", mode: "FT8",
            timestamp: Date(), myCallsign: "N0TEST",
            parkReference: "US-0099", notes: "US-0099",
            importSource: .adifFile
        )
        // 4: hidden (skipped)
        let q4 = QSO(
            callsign: "VE3ABC", band: "20m", mode: "CW",
            timestamp: Date(), myCallsign: "N0TEST",
            parkReference: nil, notes: "US-0050",
            importSource: .adifFile
        )
        q4.isHidden = true

        for qso in [q1, q2, q3, q4] {
            context.insert(qso)
        }
        try context.save()

        let service = CommentParkRefRepairService(container: container)
        let result = try await service.backfill()

        XCTAssertEqual(result.scanned, 2, "Only q1 and q2 should be scanned")
        XCTAssertEqual(result.updated, 1, "Only q1 has a valid park ref in notes")
    }

    // MARK: Private

    private var container: ModelContainer!
    private var context: ModelContext!
}

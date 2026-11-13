import CarrierWaveData
import SwiftData
import XCTest
@testable import CarrierWave

/// Tests for OPPrefixBackfillService.
///
/// Runs the SwiftData #Predicate against a real in-memory store to catch
/// predicate-translation crashes before deployment, and verifies the
/// segment-stripping logic across the joiner shapes that pre-CAR-243
/// `combineNotes` could emit.
@MainActor
final class OPPrefixBackfillServiceTests: XCTestCase {
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

    func testPredicateDoesNotCrashOnEmptyStore() async throws {
        let service = OPPrefixBackfillService(container: container)
        let result = try await service.backfill()

        XCTAssertEqual(result.scanned, 0)
        XCTAssertEqual(result.repaired, 0)
    }

    // MARK: - Pure stripping logic

    func testStripsBareOPSegmentToEmpty() {
        XCTAssertEqual(OPPrefixBackfillService.stripOPSegments("OP: Bob"), "")
    }

    func testStripsLeadingOPSegment() {
        XCTAssertEqual(
            OPPrefixBackfillService.stripOPSegments("OP: Bob | QRM here"),
            "QRM here"
        )
    }

    func testStripsTrailingOPSegment() {
        XCTAssertEqual(
            OPPrefixBackfillService.stripOPSegments("session note | OP: Bob"),
            "session note"
        )
    }

    func testStripsMiddleOPSegment() {
        XCTAssertEqual(
            OPPrefixBackfillService.stripOPSegments("session | OP: Bob | notes"),
            "session | notes"
        )
    }

    /// Pre-CAR-243 `operatorName` could include spaces ("Marshall R"); the
    /// strip walks segment boundaries, not whitespace, so spaces inside the
    /// name are preserved as part of the stripped segment.
    func testStripsOPSegmentWithSpacesInName() {
        XCTAssertEqual(
            OPPrefixBackfillService.stripOPSegments("OP: Marshall R | notes"),
            "notes"
        )
    }

    func testLeavesUnrelatedNotesUntouched() {
        let untouched = "POTA US-1234 | something normal"
        XCTAssertEqual(OPPrefixBackfillService.stripOPSegments(untouched), untouched)
    }

    /// `OP:` without the trailing space (or other formatting) is not the
    /// legacy prefix and must be preserved.
    func testDoesNotStripOpWithoutTrailingSpace() {
        XCTAssertEqual(
            OPPrefixBackfillService.stripOPSegments("OP:NoSpace | notes"),
            "OP:NoSpace | notes"
        )
    }

    func testCaseSensitiveDoesNotStripLowercase() {
        XCTAssertEqual(
            OPPrefixBackfillService.stripOPSegments("op: alice | notes"),
            "op: alice | notes"
        )
    }

    // MARK: - End-to-end backfill

    func testBackfillStripsAndClearsNotesWhenEntirelyOP() async throws {
        let qso = QSO(
            callsign: "W1AW", band: "20m", mode: "CW",
            timestamp: Date(), myCallsign: "N0TEST",
            notes: "OP: Alice",
            notesUserAuthored: false,
            importSource: .adifFile
        )
        context.insert(qso)
        try context.save()

        let service = OPPrefixBackfillService(container: container)
        let result = try await service.backfill()

        XCTAssertEqual(result.scanned, 1)
        XCTAssertEqual(result.repaired, 1)

        let descriptor = BoundedDescriptor<QSO>(limit: 10)
        let fetched = try context.boundedFetch(descriptor)
        XCTAssertNil(fetched.first?.notes)
    }

    func testBackfillStripsLeadingOPSegment() async throws {
        let qso = QSO(
            callsign: "W1AW", band: "20m", mode: "CW",
            timestamp: Date(), myCallsign: "N0TEST",
            notes: "OP: Alice | actual notes",
            notesUserAuthored: false,
            importSource: .adifFile
        )
        context.insert(qso)
        try context.save()

        let service = OPPrefixBackfillService(container: container)
        let result = try await service.backfill()

        XCTAssertEqual(result.repaired, 1)
        let fetched = try context.boundedFetch(BoundedDescriptor<QSO>(limit: 10))
        XCTAssertEqual(fetched.first?.notes, "actual notes")
    }

    func testBackfillSkipsUserAuthoredNotes() async throws {
        let qso = QSO(
            callsign: "W1AW", band: "20m", mode: "CW",
            timestamp: Date(), myCallsign: "N0TEST",
            notes: "OP: Alice | typed by hand",
            notesUserAuthored: true,
            importSource: .adifFile
        )
        context.insert(qso)
        try context.save()

        let service = OPPrefixBackfillService(container: container)
        let result = try await service.backfill()

        XCTAssertEqual(result.scanned, 0)
        XCTAssertEqual(result.repaired, 0)
        let fetched = try context.boundedFetch(BoundedDescriptor<QSO>(limit: 10))
        XCTAssertEqual(fetched.first?.notes, "OP: Alice | typed by hand")
    }

    func testBackfillSkipsNotesWithoutOPSegment() async throws {
        let qso = QSO(
            callsign: "W1AW", band: "20m", mode: "CW",
            timestamp: Date(), myCallsign: "N0TEST",
            notes: "casual contact",
            notesUserAuthored: false,
            importSource: .adifFile
        )
        context.insert(qso)
        try context.save()

        let service = OPPrefixBackfillService(container: container)
        let result = try await service.backfill()

        XCTAssertEqual(result.scanned, 1)
        XCTAssertEqual(result.repaired, 0)
        let fetched = try context.boundedFetch(BoundedDescriptor<QSO>(limit: 10))
        XCTAssertEqual(fetched.first?.notes, "casual contact")
    }

    func testBackfillSkipsNilNotes() async throws {
        let qso = QSO(
            callsign: "W1AW", band: "20m", mode: "CW",
            timestamp: Date(), myCallsign: "N0TEST",
            notes: nil,
            notesUserAuthored: false,
            importSource: .adifFile
        )
        context.insert(qso)
        try context.save()

        let service = OPPrefixBackfillService(container: container)
        let result = try await service.backfill()

        XCTAssertEqual(result.scanned, 0)
        XCTAssertEqual(result.repaired, 0)
    }

    // MARK: Private

    private var container: ModelContainer!
    private var context: ModelContext!
}

import SwiftData
import XCTest
@testable import CarrierWave

/// Tests for LoggingSession rove accessors and lifecycle
final class LoggingSessionRoveTests: XCTestCase {
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!

    @MainActor
    override func setUp() async throws {
        let (container, context) = try TestModelContainer.createWithContext()
        modelContainer = container
        modelContext = context
    }

    // MARK: - Rove Accessor Tests

    @MainActor
    func testRoveStops_emptyByDefault() {
        let session = LoggingSession.testSession()
        XCTAssertTrue(session.roveStops.isEmpty)
        XCTAssertEqual(session.roveStopCount, 0)
        XCTAssertNil(session.currentRoveStop)
    }

    @MainActor
    func testRoveStops_roundTrip() {
        let session = LoggingSession.testSession()
        let stops = [
            RoveStop(parkReference: "US-0001", startedAt: Date(), qsoCount: 5),
            RoveStop(parkReference: "US-0002", startedAt: Date()),
        ]
        session.roveStops = stops

        XCTAssertEqual(session.roveStopCount, 2)
        XCTAssertEqual(session.roveStops[0].parkReference, "US-0001")
        XCTAssertEqual(session.roveStops[0].qsoCount, 5)
        XCTAssertEqual(session.roveStops[1].parkReference, "US-0002")
    }

    @MainActor
    func testCurrentRoveStop_returnsActiveStop() {
        let session = LoggingSession.testSession()
        session.roveStops = [
            RoveStop(
                parkReference: "US-0001",
                startedAt: Date(),
                endedAt: Date(),
                qsoCount: 10
            ),
            RoveStop(parkReference: "US-0002", startedAt: Date()),
        ]

        let current = session.currentRoveStop
        XCTAssertNotNil(current)
        XCTAssertEqual(current?.parkReference, "US-0002")
    }

    @MainActor
    func testCurrentRoveStop_allClosed_returnsLast() {
        let session = LoggingSession.testSession()
        session.roveStops = [
            RoveStop(
                parkReference: "US-0001",
                startedAt: Date(),
                endedAt: Date()
            ),
            RoveStop(
                parkReference: "US-0002",
                startedAt: Date(),
                endedAt: Date()
            ),
        ]

        let current = session.currentRoveStop
        XCTAssertNotNil(current)
        XCTAssertEqual(current?.parkReference, "US-0002")
    }

    @MainActor
    func testRoveTotalQSOCount() {
        let session = LoggingSession.testSession()
        session.roveStops = [
            RoveStop(parkReference: "US-0001", startedAt: Date(), qsoCount: 12),
            RoveStop(parkReference: "US-0002", startedAt: Date(), qsoCount: 8),
            RoveStop(parkReference: "US-0003", startedAt: Date(), qsoCount: 7),
        ]
        XCTAssertEqual(session.roveTotalQSOCount, 27)
    }

    // MARK: - Default Title

    @MainActor
    func testDefaultTitle_roveWithStops() {
        let session = LoggingSession.testSession(
            activationType: .pota,
            parkReference: "US-0003"
        )
        session.isRove = true
        session.roveStops = [
            RoveStop(parkReference: "US-0001", startedAt: Date()),
            RoveStop(parkReference: "US-0002", startedAt: Date()),
            RoveStop(parkReference: "US-0003", startedAt: Date()),
        ]
        XCTAssertEqual(session.defaultTitle, "N0TEST Rove (3 parks)")
    }

    @MainActor
    func testDefaultTitle_roveSinglePark() {
        let session = LoggingSession.testSession(
            activationType: .pota,
            parkReference: "US-0001"
        )
        session.isRove = true
        session.roveStops = [
            RoveStop(parkReference: "US-0001", startedAt: Date()),
        ]
        XCTAssertEqual(session.defaultTitle, "N0TEST Rove (1 park)")
    }

    @MainActor
    func testDefaultTitle_roveNoStops() {
        let session = LoggingSession.testSession(activationType: .pota)
        session.isRove = true
        XCTAssertEqual(session.defaultTitle, "N0TEST POTA Rove")
    }

    @MainActor
    func testDefaultTitle_nonRovePOTA_unchanged() {
        let session = LoggingSession.testSession(
            activationType: .pota,
            parkReference: "US-0001"
        )
        XCTAssertFalse(session.isRove)
        XCTAssertEqual(session.defaultTitle, "N0TEST at US-0001")
    }

    // MARK: - IsRove Flag

    @MainActor
    func testIsRove_defaultsFalse() {
        let session = LoggingSession.testSession()
        XCTAssertFalse(session.isRove)
    }

    @MainActor
    func testIsRove_persistsThroughSwiftData() throws {
        let session = LoggingSession.testSession(
            activationType: .pota,
            parkReference: "US-0001"
        )
        session.isRove = true
        session.roveStops = [
            RoveStop(parkReference: "US-0001", startedAt: Date()),
        ]

        modelContext.insert(session)
        try modelContext.save()

        let descriptor = FetchDescriptor<LoggingSession>()
        let fetched = try modelContext.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertTrue(fetched[0].isRove)
        XCTAssertEqual(fetched[0].roveStopCount, 1)
    }
}

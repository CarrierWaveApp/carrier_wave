import CarrierWaveCore
import SwiftData
import XCTest
@testable import CarrierWave

/// Tests for LoggingSession model
///
/// These tests cover:
/// - Session state transitions
/// - Band derivation from frequency
/// - Duration calculations
/// - Display title generation (in +DisplayAndPersistence)
/// - Spot comments serialization (in +DisplayAndPersistence)
final class LoggingSessionTests: XCTestCase {
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!

    @MainActor
    override func setUp() async throws {
        let (container, context) = try TestModelContainer.createWithContext()
        modelContainer = container
        modelContext = context
    }

    // MARK: - Initialization Tests

    @MainActor
    func testInit_DefaultValues() {
        // When
        let session = LoggingSession(myCallsign: "N0TEST")

        // Then
        XCTAssertEqual(session.myCallsign, "N0TEST")
        XCTAssertEqual(session.mode, "CW")
        XCTAssertEqual(session.activationType, .casual)
        XCTAssertEqual(session.status, .active)
        XCTAssertEqual(session.qsoCount, 0)
        XCTAssertNil(session.endedAt)
        XCTAssertNil(session.parkReference)
        XCTAssertNil(session.sotaReference)
    }

    @MainActor
    func testInit_WithAllFields() {
        // When
        let session = LoggingSession(
            myCallsign: "N0TEST",
            startedAt: Date(),
            frequency: 14.060,
            mode: "SSB",
            activationType: .pota,
            parkReference: "US-0001",
            sotaReference: nil,
            myGrid: "FN31",
            notes: "Test notes"
        )

        // Then
        XCTAssertEqual(session.mode, "SSB")
        XCTAssertEqual(session.activationType, .pota)
        XCTAssertEqual(session.parkReference, "US-0001")
        XCTAssertEqual(session.myGrid, "FN31")
        XCTAssertEqual(session.notes, "Test notes")
    }

    // MARK: - State Transition Tests

    @MainActor
    func testEnd_SetsCompletedStatusAndEndTime() {
        // Given
        let session = LoggingSession(myCallsign: "N0TEST")
        XCTAssertTrue(session.isActive)
        XCTAssertNil(session.endedAt)

        // When
        session.end()

        // Then
        XCTAssertEqual(session.status, .completed)
        XCTAssertFalse(session.isActive)
        XCTAssertNotNil(session.endedAt)
    }

    @MainActor
    func testPause_SetsPausedStatus() {
        // Given
        let session = LoggingSession(myCallsign: "N0TEST")

        // When
        session.pause()

        // Then
        XCTAssertEqual(session.status, .paused)
        XCTAssertFalse(session.isActive)
    }

    @MainActor
    func testResume_SetsActiveStatus() {
        // Given
        let session = LoggingSession(myCallsign: "N0TEST")
        session.pause()

        // When
        session.resume()

        // Then
        XCTAssertEqual(session.status, .active)
        XCTAssertTrue(session.isActive)
    }

    // MARK: - Band Derivation Tests

    @MainActor
    func testBandForFrequency_160m() {
        XCTAssertEqual(LoggingSession.bandForFrequency(1.810), "160m")
        XCTAssertEqual(LoggingSession.bandForFrequency(1.900), "160m")
        XCTAssertEqual(LoggingSession.bandForFrequency(1.999), "160m")
    }

    @MainActor
    func testBandForFrequency_80m() {
        XCTAssertEqual(LoggingSession.bandForFrequency(3.530), "80m")
        XCTAssertEqual(LoggingSession.bandForFrequency(3.850), "80m")
    }

    @MainActor
    func testBandForFrequency_60m() {
        XCTAssertEqual(LoggingSession.bandForFrequency(5.332), "60m")
    }

    @MainActor
    func testBandForFrequency_40m() {
        XCTAssertEqual(LoggingSession.bandForFrequency(7.030), "40m")
        XCTAssertEqual(LoggingSession.bandForFrequency(7.200), "40m")
    }

    @MainActor
    func testBandForFrequency_30m() {
        XCTAssertEqual(LoggingSession.bandForFrequency(10.106), "30m")
    }

    @MainActor
    func testBandForFrequency_20m() {
        XCTAssertEqual(LoggingSession.bandForFrequency(14.060), "20m")
        XCTAssertEqual(LoggingSession.bandForFrequency(14.250), "20m")
    }

    @MainActor
    func testBandForFrequency_17m() {
        XCTAssertEqual(LoggingSession.bandForFrequency(18.080), "17m")
    }

    @MainActor
    func testBandForFrequency_15m() {
        XCTAssertEqual(LoggingSession.bandForFrequency(21.060), "15m")
        XCTAssertEqual(LoggingSession.bandForFrequency(21.300), "15m")
    }

    @MainActor
    func testBandForFrequency_12m() {
        XCTAssertEqual(LoggingSession.bandForFrequency(24.910), "12m")
    }

    @MainActor
    func testBandForFrequency_10m() {
        XCTAssertEqual(LoggingSession.bandForFrequency(28.060), "10m")
        XCTAssertEqual(LoggingSession.bandForFrequency(28.400), "10m")
    }

    @MainActor
    func testBandForFrequency_6m() {
        XCTAssertEqual(LoggingSession.bandForFrequency(50.313), "6m")
    }

    @MainActor
    func testBandForFrequency_2m() {
        XCTAssertEqual(LoggingSession.bandForFrequency(144.174), "2m")
    }

    @MainActor
    func testBandForFrequency_70cm() {
        XCTAssertEqual(LoggingSession.bandForFrequency(432.100), "70cm")
    }

    @MainActor
    func testBandForFrequency_Unknown() {
        XCTAssertEqual(LoggingSession.bandForFrequency(1.0), "Unknown")
        XCTAssertEqual(LoggingSession.bandForFrequency(100.0), "Unknown")
    }

    @MainActor
    func testBand_DerivedFromFrequency() {
        // Given
        let session = LoggingSession(myCallsign: "N0TEST", frequency: 14.060)

        // Then
        XCTAssertEqual(session.band, "20m")
    }

    @MainActor
    func testBand_NilWhenNoFrequency() {
        // Given
        let session = LoggingSession(myCallsign: "N0TEST")

        // Then
        XCTAssertNil(session.band)
    }

    // MARK: - Duration Tests

    @MainActor
    func testDuration_ActiveSession() {
        // Given
        let startTime = Date().addingTimeInterval(-3_600) // 1 hour ago
        let session = LoggingSession(myCallsign: "N0TEST", startedAt: startTime)

        // Then - duration should be approximately 1 hour
        let duration = session.duration
        XCTAssertGreaterThan(duration, 3_500)
        XCTAssertLessThan(duration, 3_700)
    }

    @MainActor
    func testDuration_EndedSession() {
        // Given
        let startTime = Date().addingTimeInterval(-7_200) // 2 hours ago
        let session = LoggingSession(myCallsign: "N0TEST", startedAt: startTime)
        session.end()

        // Then - duration should be approximately 2 hours
        let duration = session.duration
        XCTAssertGreaterThan(duration, 7_100)
        XCTAssertLessThan(duration, 7_300)
    }

    @MainActor
    func testFormattedDuration_HoursAndMinutes() {
        // Given - 1 hour 23 minutes
        let startTime = Date().addingTimeInterval(-(3_600 + 23 * 60))
        let session = LoggingSession(myCallsign: "N0TEST", startedAt: startTime)
        session.end()

        // Then
        XCTAssertEqual(session.formattedDuration, "1h 23m")
    }

    @MainActor
    func testFormattedDuration_MinutesOnly() {
        // Given - 45 minutes
        let startTime = Date().addingTimeInterval(-45 * 60)
        let session = LoggingSession(myCallsign: "N0TEST", startedAt: startTime)
        session.end()

        // Then
        XCTAssertEqual(session.formattedDuration, "45m")
    }
}

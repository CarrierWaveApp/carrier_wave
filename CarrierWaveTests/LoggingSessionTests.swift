import SwiftData
import XCTest
@testable import CarrierWave

/// Tests for LoggingSession model
///
/// These tests cover:
/// - Session state transitions
/// - Band derivation from frequency
/// - Duration calculations
/// - Display title generation
/// - Spot comments serialization
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
    func testInit_DefaultValues() throws {
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
    func testInit_WithAllFields() throws {
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
    func testEnd_SetsCompletedStatusAndEndTime() throws {
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
    func testPause_SetsPausedStatus() throws {
        // Given
        let session = LoggingSession(myCallsign: "N0TEST")

        // When
        session.pause()

        // Then
        XCTAssertEqual(session.status, .paused)
        XCTAssertFalse(session.isActive)
    }

    @MainActor
    func testResume_SetsActiveStatus() throws {
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
    func testBandForFrequency_160m() throws {
        XCTAssertEqual(LoggingSession.bandForFrequency(1.810), "160m")
        XCTAssertEqual(LoggingSession.bandForFrequency(1.900), "160m")
        XCTAssertEqual(LoggingSession.bandForFrequency(1.999), "160m")
    }

    @MainActor
    func testBandForFrequency_80m() throws {
        XCTAssertEqual(LoggingSession.bandForFrequency(3.530), "80m")
        XCTAssertEqual(LoggingSession.bandForFrequency(3.850), "80m")
    }

    @MainActor
    func testBandForFrequency_60m() throws {
        XCTAssertEqual(LoggingSession.bandForFrequency(5.332), "60m")
    }

    @MainActor
    func testBandForFrequency_40m() throws {
        XCTAssertEqual(LoggingSession.bandForFrequency(7.030), "40m")
        XCTAssertEqual(LoggingSession.bandForFrequency(7.200), "40m")
    }

    @MainActor
    func testBandForFrequency_30m() throws {
        XCTAssertEqual(LoggingSession.bandForFrequency(10.106), "30m")
    }

    @MainActor
    func testBandForFrequency_20m() throws {
        XCTAssertEqual(LoggingSession.bandForFrequency(14.060), "20m")
        XCTAssertEqual(LoggingSession.bandForFrequency(14.250), "20m")
    }

    @MainActor
    func testBandForFrequency_17m() throws {
        XCTAssertEqual(LoggingSession.bandForFrequency(18.080), "17m")
    }

    @MainActor
    func testBandForFrequency_15m() throws {
        XCTAssertEqual(LoggingSession.bandForFrequency(21.060), "15m")
        XCTAssertEqual(LoggingSession.bandForFrequency(21.300), "15m")
    }

    @MainActor
    func testBandForFrequency_12m() throws {
        XCTAssertEqual(LoggingSession.bandForFrequency(24.910), "12m")
    }

    @MainActor
    func testBandForFrequency_10m() throws {
        XCTAssertEqual(LoggingSession.bandForFrequency(28.060), "10m")
        XCTAssertEqual(LoggingSession.bandForFrequency(28.400), "10m")
    }

    @MainActor
    func testBandForFrequency_6m() throws {
        XCTAssertEqual(LoggingSession.bandForFrequency(50.313), "6m")
    }

    @MainActor
    func testBandForFrequency_2m() throws {
        XCTAssertEqual(LoggingSession.bandForFrequency(144.174), "2m")
    }

    @MainActor
    func testBandForFrequency_70cm() throws {
        XCTAssertEqual(LoggingSession.bandForFrequency(432.100), "70cm")
    }

    @MainActor
    func testBandForFrequency_Unknown() throws {
        XCTAssertEqual(LoggingSession.bandForFrequency(1.0), "Unknown")
        XCTAssertEqual(LoggingSession.bandForFrequency(100.0), "Unknown")
    }

    @MainActor
    func testBand_DerivedFromFrequency() throws {
        // Given
        let session = LoggingSession(myCallsign: "N0TEST", frequency: 14.060)

        // Then
        XCTAssertEqual(session.band, "20m")
    }

    @MainActor
    func testBand_NilWhenNoFrequency() throws {
        // Given
        let session = LoggingSession(myCallsign: "N0TEST")

        // Then
        XCTAssertNil(session.band)
    }

    // MARK: - Duration Tests

    @MainActor
    func testDuration_ActiveSession() throws {
        // Given
        let startTime = Date().addingTimeInterval(-3600) // 1 hour ago
        let session = LoggingSession(myCallsign: "N0TEST", startedAt: startTime)

        // Then - duration should be approximately 1 hour
        let duration = session.duration
        XCTAssertGreaterThan(duration, 3500)
        XCTAssertLessThan(duration, 3700)
    }

    @MainActor
    func testDuration_EndedSession() throws {
        // Given
        let startTime = Date().addingTimeInterval(-7200) // 2 hours ago
        let session = LoggingSession(myCallsign: "N0TEST", startedAt: startTime)
        session.end()

        // Then - duration should be approximately 2 hours
        let duration = session.duration
        XCTAssertGreaterThan(duration, 7100)
        XCTAssertLessThan(duration, 7300)
    }

    @MainActor
    func testFormattedDuration_HoursAndMinutes() throws {
        // Given - 1 hour 23 minutes
        let startTime = Date().addingTimeInterval(-(3600 + 23 * 60))
        let session = LoggingSession(myCallsign: "N0TEST", startedAt: startTime)
        session.end()

        // Then
        XCTAssertEqual(session.formattedDuration, "1h 23m")
    }

    @MainActor
    func testFormattedDuration_MinutesOnly() throws {
        // Given - 45 minutes
        let startTime = Date().addingTimeInterval(-45 * 60)
        let session = LoggingSession(myCallsign: "N0TEST", startedAt: startTime)
        session.end()

        // Then
        XCTAssertEqual(session.formattedDuration, "45m")
    }

    // MARK: - Display Title Tests

    @MainActor
    func testDisplayTitle_CasualSession() throws {
        // Given
        let session = LoggingSession(
            myCallsign: "N0TEST",
            activationType: .casual
        )

        // Then
        XCTAssertEqual(session.displayTitle, "N0TEST Casual")
        XCTAssertEqual(session.defaultTitle, "N0TEST Casual")
    }

    @MainActor
    func testDisplayTitle_POTASessionWithPark() throws {
        // Given
        let session = LoggingSession(
            myCallsign: "N0TEST",
            activationType: .pota,
            parkReference: "US-0001"
        )

        // Then
        XCTAssertEqual(session.displayTitle, "N0TEST at US-0001")
    }

    @MainActor
    func testDisplayTitle_POTASessionWithoutPark() throws {
        // Given
        let session = LoggingSession(
            myCallsign: "N0TEST",
            activationType: .pota
        )

        // Then
        XCTAssertEqual(session.displayTitle, "N0TEST POTA")
    }

    @MainActor
    func testDisplayTitle_SOTASessionWithSummit() throws {
        // Given
        let session = LoggingSession(
            myCallsign: "N0TEST",
            activationType: .sota,
            sotaReference: "W4C/CM-001"
        )

        // Then
        XCTAssertEqual(session.displayTitle, "N0TEST at W4C/CM-001")
    }

    @MainActor
    func testDisplayTitle_CustomTitleOverridesDefault() throws {
        // Given
        let session = LoggingSession(
            myCallsign: "N0TEST",
            activationType: .pota,
            parkReference: "US-0001"
        )
        session.customTitle = "Field Day at the Lake"

        // Then
        XCTAssertEqual(session.displayTitle, "Field Day at the Lake")
        XCTAssertEqual(session.defaultTitle, "N0TEST at US-0001")
    }

    // MARK: - Activation Reference Tests

    @MainActor
    func testActivationReference_POTA() throws {
        let session = LoggingSession(
            myCallsign: "N0TEST",
            activationType: .pota,
            parkReference: "US-0001"
        )
        XCTAssertEqual(session.activationReference, "US-0001")
    }

    @MainActor
    func testActivationReference_SOTA() throws {
        let session = LoggingSession(
            myCallsign: "N0TEST",
            activationType: .sota,
            sotaReference: "W4C/CM-001"
        )
        XCTAssertEqual(session.activationReference, "W4C/CM-001")
    }

    @MainActor
    func testActivationReference_Casual() throws {
        let session = LoggingSession(
            myCallsign: "N0TEST",
            activationType: .casual
        )
        XCTAssertNil(session.activationReference)
    }

    // MARK: - QSO Count Tests

    @MainActor
    func testIncrementQSOCount() throws {
        // Given
        let session = LoggingSession(myCallsign: "N0TEST")
        XCTAssertEqual(session.qsoCount, 0)

        // When
        session.incrementQSOCount()
        session.incrementQSOCount()
        session.incrementQSOCount()

        // Then
        XCTAssertEqual(session.qsoCount, 3)
    }

    // MARK: - Frequency/Mode Update Tests

    @MainActor
    func testUpdateFrequency() throws {
        // Given
        let session = LoggingSession(myCallsign: "N0TEST", frequency: 14.060)

        // When
        session.updateFrequency(7.030)

        // Then
        XCTAssertEqual(session.frequency, 7.030)
        XCTAssertEqual(session.band, "40m")
    }

    @MainActor
    func testUpdateMode_Uppercases() throws {
        // Given
        let session = LoggingSession(myCallsign: "N0TEST", mode: "CW")

        // When
        session.updateMode("ssb")

        // Then
        XCTAssertEqual(session.mode, "SSB")
    }

    // MARK: - Suggested Frequencies Tests

    @MainActor
    func testSuggestedFrequencies_CW() throws {
        let frequencies = LoggingSession.suggestedFrequencies(for: "CW")

        XCTAssertEqual(frequencies["20m"], 14.060)
        XCTAssertEqual(frequencies["40m"], 7.030)
        XCTAssertEqual(frequencies["80m"], 3.530)
    }

    @MainActor
    func testSuggestedFrequencies_SSB() throws {
        let frequencies = LoggingSession.suggestedFrequencies(for: "SSB")

        XCTAssertEqual(frequencies["20m"], 14.250)
        XCTAssertEqual(frequencies["40m"], 7.200)
        XCTAssertEqual(frequencies["80m"], 3.850)
    }

    @MainActor
    func testSuggestedFrequencies_USB() throws {
        // USB should use SSB frequencies
        let frequencies = LoggingSession.suggestedFrequencies(for: "USB")

        XCTAssertEqual(frequencies["20m"], 14.250)
    }

    @MainActor
    func testSuggestedFrequencies_UnknownMode_DefaultsToCW() throws {
        let frequencies = LoggingSession.suggestedFrequencies(for: "FT8")

        // FT8 isn't specially handled, defaults to CW frequencies
        XCTAssertEqual(frequencies["20m"], 14.060)
    }

    // MARK: - Persistence Tests

    @MainActor
    func testPersistence_RoundTrip() throws {
        // Given
        let session = LoggingSession(
            myCallsign: "N0TEST",
            frequency: 14.060,
            mode: "SSB",
            activationType: .pota,
            parkReference: "US-0001",
            myGrid: "FN31"
        )
        session.customTitle = "Test Session"
        session.qsoCount = 5

        modelContext.insert(session)
        try modelContext.save()

        // When - fetch from database
        let descriptor = FetchDescriptor<LoggingSession>()
        let fetched = try modelContext.fetch(descriptor).first!

        // Then
        XCTAssertEqual(fetched.myCallsign, "N0TEST")
        XCTAssertEqual(fetched.frequency, 14.060)
        XCTAssertEqual(fetched.mode, "SSB")
        XCTAssertEqual(fetched.activationType, .pota)
        XCTAssertEqual(fetched.parkReference, "US-0001")
        XCTAssertEqual(fetched.myGrid, "FN31")
        XCTAssertEqual(fetched.customTitle, "Test Session")
        XCTAssertEqual(fetched.qsoCount, 5)
    }
}

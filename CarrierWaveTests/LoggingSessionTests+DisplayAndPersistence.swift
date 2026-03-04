import CarrierWaveCore
import CarrierWaveData
import SwiftData
import XCTest
@testable import CarrierWave

// MARK: - Display Title, Activation Reference, Frequency, and Persistence Tests

extension LoggingSessionTests {
    // MARK: - Display Title Tests

    @MainActor
    func testDisplayTitle_CasualSession() {
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
    func testDisplayTitle_POTASessionWithPark() {
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
    func testDisplayTitle_POTASessionWithoutPark() {
        // Given
        let session = LoggingSession(
            myCallsign: "N0TEST",
            activationType: .pota
        )

        // Then
        XCTAssertEqual(session.displayTitle, "N0TEST POTA")
    }

    @MainActor
    func testDisplayTitle_SOTASessionWithSummit() {
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
    func testDisplayTitle_CustomTitleOverridesDefault() {
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
    func testActivationReference_POTA() {
        let session = LoggingSession(
            myCallsign: "N0TEST",
            activationType: .pota,
            parkReference: "US-0001"
        )
        XCTAssertEqual(session.activationReference, "US-0001")
    }

    @MainActor
    func testActivationReference_SOTA() {
        let session = LoggingSession(
            myCallsign: "N0TEST",
            activationType: .sota,
            sotaReference: "W4C/CM-001"
        )
        XCTAssertEqual(session.activationReference, "W4C/CM-001")
    }

    @MainActor
    func testActivationReference_Casual() {
        let session = LoggingSession(
            myCallsign: "N0TEST",
            activationType: .casual
        )
        XCTAssertNil(session.activationReference)
    }

    // MARK: - QSO Count Tests

    @MainActor
    func testIncrementQSOCount() {
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
    func testUpdateFrequency() {
        // Given
        let session = LoggingSession(myCallsign: "N0TEST", frequency: 14.060)

        // When
        session.updateFrequency(7.030)

        // Then
        XCTAssertEqual(session.frequency, 7.030)
        XCTAssertEqual(session.band, "40m")
    }

    @MainActor
    func testUpdateMode_Uppercases() {
        // Given
        let session = LoggingSession(myCallsign: "N0TEST", mode: "CW")

        // When
        session.updateMode("ssb")

        // Then
        XCTAssertEqual(session.mode, "SSB")
    }

    // MARK: - Suggested Frequencies Tests

    @MainActor
    func testSuggestedFrequencies_CW() {
        let frequencies = LoggingSession.suggestedFrequencies(for: "CW")

        XCTAssertEqual(frequencies["20m"], 14.060)
        XCTAssertEqual(frequencies["40m"], 7.030)
        XCTAssertEqual(frequencies["80m"], 3.530)
    }

    @MainActor
    func testSuggestedFrequencies_SSB() {
        let frequencies = LoggingSession.suggestedFrequencies(for: "SSB")

        XCTAssertEqual(frequencies["20m"], 14.250)
        XCTAssertEqual(frequencies["40m"], 7.200)
        XCTAssertEqual(frequencies["80m"], 3.850)
    }

    @MainActor
    func testSuggestedFrequencies_USB() {
        // USB should use SSB frequencies
        let frequencies = LoggingSession.suggestedFrequencies(for: "USB")

        XCTAssertEqual(frequencies["20m"], 14.250)
    }

    @MainActor
    func testSuggestedFrequencies_UnknownMode_DefaultsToCW() {
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
        let fetched = try XCTUnwrap(try modelContext.fetch(descriptor).first)

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

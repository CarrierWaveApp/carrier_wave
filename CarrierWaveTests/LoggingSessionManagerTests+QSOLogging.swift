import CarrierWaveCore
import SwiftData
import XCTest
@testable import CarrierWave

// MARK: - QSO Logging Tests

extension LoggingSessionManagerTests {
    @MainActor
    func testLogQSO_CreatesQSOWithSessionFields() {
        // Given
        sessionManager.startSession(
            myCallsign: "N0TEST",
            mode: "CW",
            frequency: 14.060,
            activationType: .pota,
            parkReference: "US-0001",
            myGrid: "FN31"
        )

        // When
        let qso = sessionManager.logQSO(
            callsign: "W1AW",
            rstSent: "599",
            rstReceived: "579",
            theirGrid: "FN42"
        )

        // Then
        XCTAssertNotNil(qso)
        XCTAssertEqual(qso?.callsign, "W1AW")
        XCTAssertEqual(qso?.mode, "CW")
        XCTAssertEqual(qso?.frequency, 14.060)
        XCTAssertEqual(qso?.band, "20m")
        XCTAssertEqual(qso?.myCallsign, "N0TEST")
        XCTAssertEqual(qso?.myGrid, "FN31")
        XCTAssertEqual(qso?.parkReference, "US-0001")
        XCTAssertEqual(qso?.theirGrid, "FN42")
        XCTAssertEqual(qso?.importSource, .logger)
        XCTAssertNotNil(qso?.loggingSessionId)
    }

    @MainActor
    func testLogQSO_UppercasesCallsign() {
        // Given
        sessionManager.startSession(myCallsign: "N0TEST", mode: "CW", frequency: 14.060)

        // When
        let qso = sessionManager.logQSO(callsign: "w1aw")

        // Then
        XCTAssertEqual(qso?.callsign, "W1AW")
    }

    @MainActor
    func testLogQSO_IncrementsSessionQSOCount() {
        // Given
        sessionManager.startSession(myCallsign: "N0TEST", mode: "CW", frequency: 14.060)
        XCTAssertEqual(sessionManager.activeSession?.qsoCount, 0)

        // When
        _ = sessionManager.logQSO(callsign: "W1AW")
        _ = sessionManager.logQSO(callsign: "K3LR")

        // Then
        XCTAssertEqual(sessionManager.activeSession?.qsoCount, 2)
    }

    @MainActor
    func testLogQSO_WithoutActiveSession_ReturnsNil() {
        // Given - no active session
        XCTAssertFalse(sessionManager.hasActiveSession)

        // When
        let qso = sessionManager.logQSO(callsign: "W1AW")

        // Then
        XCTAssertNil(qso)
    }

    @MainActor
    func testLogQSO_WithTheirParkReference() {
        // Given - POTA session
        sessionManager.startSession(
            myCallsign: "N0TEST",
            mode: "CW",
            frequency: 14.060,
            activationType: .pota,
            parkReference: "US-0001"
        )

        // When - log P2P QSO
        let qso = sessionManager.logQSO(
            callsign: "W1AW",
            theirParkReference: "US-0002"
        )

        // Then
        XCTAssertEqual(qso?.parkReference, "US-0001")
        XCTAssertEqual(qso?.theirParkReference, "US-0002")
    }

    @MainActor
    func testLogQSO_CombinesNotesAndOperatorName() {
        // Given
        sessionManager.startSession(myCallsign: "N0TEST", mode: "CW", frequency: 14.060)

        // When
        let qso = sessionManager.logQSO(
            callsign: "W1AW",
            notes: "Great signal",
            operatorName: "Bob"
        )

        // Then
        XCTAssertEqual(qso?.notes, "OP: Bob | Great signal")
    }

    // MARK: - Frequency and Mode Updates

    @MainActor
    func testUpdateFrequency_UpdatesSessionFrequency() {
        // Given
        sessionManager.startSession(myCallsign: "N0TEST", mode: "CW", frequency: 14.060)

        // When
        _ = sessionManager.updateFrequency(7.030)

        // Then
        XCTAssertEqual(sessionManager.activeSession?.frequency, 7.030)
    }

    @MainActor
    func testUpdateMode_UpdatesSessionMode() {
        // Given
        sessionManager.startSession(myCallsign: "N0TEST", mode: "CW", frequency: 14.060)

        // When
        _ = sessionManager.updateMode("SSB")

        // Then
        XCTAssertEqual(sessionManager.activeSession?.mode, "SSB")
    }

    @MainActor
    func testUpdateMode_UppercasesMode() {
        // Given
        sessionManager.startSession(myCallsign: "N0TEST", mode: "CW", frequency: 14.060)

        // When
        _ = sessionManager.updateMode("ssb")

        // Then
        XCTAssertEqual(sessionManager.activeSession?.mode, "SSB")
    }

    // MARK: - Park Reference Updates

    @MainActor
    func testUpdateParkReference_POTASession() {
        // Given - POTA session
        sessionManager.startSession(
            myCallsign: "N0TEST",
            mode: "CW",
            activationType: .pota,
            parkReference: "US-0001"
        )

        // When
        sessionManager.updateParkReference("us-0002")

        // Then
        XCTAssertEqual(sessionManager.activeSession?.parkReference, "US-0002")
    }

    @MainActor
    func testUpdateParkReference_NonPOTASession_NoEffect() {
        // Given - casual session
        sessionManager.startSession(
            myCallsign: "N0TEST",
            mode: "CW",
            activationType: .casual
        )

        // When
        sessionManager.updateParkReference("US-0001")

        // Then
        XCTAssertNil(sessionManager.activeSession?.parkReference)
    }

    // MARK: - Notes Management

    @MainActor
    func testAppendNote_AddsTimestampedNote() throws {
        // Given
        sessionManager.startSession(myCallsign: "N0TEST", mode: "CW")

        // When
        sessionManager.appendNote("Starting activation")

        // Then
        let notes = sessionManager.activeSession?.notes
        XCTAssertNotNil(notes)
        XCTAssertTrue(try XCTUnwrap(notes?.contains("Starting activation")))
        XCTAssertTrue(try XCTUnwrap(notes?.contains("["))) // Has timestamp
    }

    @MainActor
    func testAppendNote_MultipleNotes() throws {
        // Given
        sessionManager.startSession(myCallsign: "N0TEST", mode: "CW")

        // When
        sessionManager.appendNote("First note")
        sessionManager.appendNote("Second note")

        // Then
        let notes = sessionManager.activeSession?.notes
        XCTAssertNotNil(notes)
        XCTAssertTrue(try XCTUnwrap(notes?.contains("First note")))
        XCTAssertTrue(try XCTUnwrap(notes?.contains("Second note")))
        XCTAssertTrue(try XCTUnwrap(notes?.contains("\n")))
    }

    @MainActor
    func testParseSessionNotes_ReturnsEntries() {
        // Given
        sessionManager.startSession(myCallsign: "N0TEST", mode: "CW")
        sessionManager.appendNote("Test note 1")
        sessionManager.appendNote("Test note 2")

        // When
        let entries = sessionManager.parseSessionNotes()

        // Then
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries[0].text.contains("Test note"))
    }
}

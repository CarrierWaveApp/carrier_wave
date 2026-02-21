import CarrierWaveCore
import SwiftData
import XCTest
@testable import CarrierWave

// MARK: - Hidden QSO Tests

extension LoggingSessionManagerTests {
    @MainActor
    func testHideQSO_SetsIsHiddenFlag() throws {
        // Given
        sessionManager.startSession(myCallsign: "N0TEST", mode: "CW", frequency: 14.060)
        let qso = try XCTUnwrap(sessionManager.logQSO(callsign: "W1AW"))

        // When
        sessionManager.hideQSO(qso)

        // Then
        XCTAssertTrue(qso.isHidden)
    }

    @MainActor
    func testUnhideQSO_ClearsIsHiddenFlag() throws {
        // Given
        sessionManager.startSession(myCallsign: "N0TEST", mode: "CW", frequency: 14.060)
        let qso = try XCTUnwrap(sessionManager.logQSO(callsign: "W1AW"))
        sessionManager.hideQSO(qso)

        // When
        sessionManager.unhideQSO(qso)

        // Then
        XCTAssertFalse(qso.isHidden)
    }

    @MainActor
    func testGetSessionQSOs_ExcludesHiddenQSOs() throws {
        // Given
        sessionManager.startSession(myCallsign: "N0TEST", mode: "CW", frequency: 14.060)
        let qso1 = try XCTUnwrap(sessionManager.logQSO(callsign: "W1AW"))
        _ = try XCTUnwrap(sessionManager.logQSO(callsign: "K3LR"))
        sessionManager.hideQSO(qso1)

        // When
        let visibleQSOs = sessionManager.getSessionQSOs()

        // Then
        XCTAssertEqual(visibleQSOs.count, 1)
        XCTAssertEqual(visibleQSOs[0].callsign, "K3LR")
    }

    @MainActor
    func testHideQSO_DecrementsSessionQSOCount() throws {
        // Given
        sessionManager.startSession(myCallsign: "N0TEST", mode: "CW", frequency: 14.060)
        let qso = try XCTUnwrap(sessionManager.logQSO(callsign: "W1AW"))
        _ = try XCTUnwrap(sessionManager.logQSO(callsign: "K3LR"))
        XCTAssertEqual(sessionManager.activeSession?.qsoCount, 2)

        // When
        sessionManager.hideQSO(qso)

        // Then
        XCTAssertEqual(sessionManager.activeSession?.qsoCount, 1)
    }

    @MainActor
    func testHideQSO_DoesNotGoNegative() throws {
        // Given — create session with manual qsoCount of 0 (edge case)
        sessionManager.startSession(myCallsign: "N0TEST", mode: "CW", frequency: 14.060)
        let qso = try XCTUnwrap(sessionManager.logQSO(callsign: "W1AW"))
        sessionManager.activeSession?.qsoCount = 0

        // When
        sessionManager.hideQSO(qso)

        // Then
        XCTAssertEqual(sessionManager.activeSession?.qsoCount, 0)
    }

    @MainActor
    func testHideQSO_IgnoresNonActiveSessionQSOs() throws {
        // Given — QSO from a different session
        sessionManager.startSession(myCallsign: "N0TEST", mode: "CW", frequency: 14.060)
        _ = try XCTUnwrap(sessionManager.logQSO(callsign: "W1AW"))
        XCTAssertEqual(sessionManager.activeSession?.qsoCount, 1)

        // Create a QSO with a different session ID
        let otherQSO = QSO(
            callsign: "K3LR", band: "20m", mode: "CW",
            timestamp: Date(), myCallsign: "N0TEST"
        )
        otherQSO.loggingSessionId = UUID()
        modelContext.insert(otherQSO)

        // When
        sessionManager.hideQSO(otherQSO)

        // Then — active session count unchanged
        XCTAssertEqual(sessionManager.activeSession?.qsoCount, 1)
        XCTAssertTrue(otherQSO.isHidden)
    }
}

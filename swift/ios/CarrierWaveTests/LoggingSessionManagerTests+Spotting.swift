import CarrierWaveData
import SwiftData
import XCTest
@testable import CarrierWave

/// Self-spot frequency selection (CAR-296).
///
/// `session.frequency` follows hunt taps so the hunted QSO logs on the right
/// frequency, but self-spots (periodic re-spot, QSY, QRT) must advertise the
/// operator's *own* running frequency — never the frequency adopted while
/// tuned to another activator.
final class LoggingSessionManagerSpottingTests: XCTestCase {
    // MARK: Internal

    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var sessionManager: LoggingSessionManager!

    // MARK: - Setup/Teardown

    @MainActor
    override func setUp() async throws {
        clearDefaults()
        // Keep every spotting path offline: no auto-spot timer, no QRT on end.
        UserDefaults.standard.set(false, forKey: "potaAutoSpotEnabled")
        UserDefaults.standard.set(false, forKey: "potaQRTSpotEnabled")
        // No solar/weather fetch: its late write-back races container teardown.
        UserDefaults.standard.set(false, forKey: "autoRecordConditions")

        let (container, context) = try TestModelContainer.createWithContext()
        modelContainer = container
        modelContext = context
        sessionManager = LoggingSessionManager(modelContext: modelContext)
    }

    @MainActor
    override func tearDown() async throws {
        if sessionManager.hasActiveSession {
            sessionManager.endSession()
        }
        clearDefaults()
        sessionManager = nil
        modelContext = nil
        modelContainer = nil
    }

    // MARK: - Hunting Must Not Move the Self-Spot Frequency

    @MainActor
    func testHuntTune_KeepsSelfSpotOnOwnFrequency() {
        // Given: activating on 7.000
        startPOTASession(frequency: 7.000)

        // When: tuning to another activator's spot on 7.054
        _ = sessionManager.updateFrequency(7.054, isTuningToSpot: true)

        // Then: the session follows the hunt, the self-spot frequency does not
        XCTAssertEqual(sessionManager.activeSession?.frequency, 7.054)
        XCTAssertEqual(sessionManager.selfSpotFrequency, 7.000)
        if let session = sessionManager.activeSession {
            XCTAssertEqual(sessionManager.spotFrequency(for: session), 7.000)
        } else {
            XCTFail("Expected an active session")
        }
    }

    @MainActor
    func testHuntTune_ChainedHuntsKeepOriginalFrequency() {
        // Given: activating on 7.000 and already tuned to one hunted station
        startPOTASession(frequency: 7.000)
        _ = sessionManager.updateFrequency(7.054, isTuningToSpot: true)

        // When: tapping a second spot without returning home first
        _ = sessionManager.updateFrequency(7.062, isTuningToSpot: true)

        // Then
        XCTAssertEqual(sessionManager.activeSession?.frequency, 7.062)
        XCTAssertEqual(sessionManager.selfSpotFrequency, 7.000)
    }

    @MainActor
    func testReturnFromHunt_RestoresOwnFrequency() {
        // Given
        startPOTASession(frequency: 7.000)
        _ = sessionManager.updateFrequency(7.054, isTuningToSpot: true)

        // When: the logger restores the pre-spot frequency (flagged as a spot tune)
        _ = sessionManager.updateFrequency(7.000, isTuningToSpot: true)

        // Then
        XCTAssertEqual(sessionManager.activeSession?.frequency, 7.000)
        XCTAssertEqual(sessionManager.selfSpotFrequency, 7.000)
    }

    // MARK: - Own QSYs Do Move It

    @MainActor
    func testManualQSY_MovesSelfSpotFrequency() {
        // Given
        startPOTASession(frequency: 7.000)

        // When: the operator QSYs (not a hunt)
        _ = sessionManager.updateFrequency(7.030)

        // Then
        XCTAssertEqual(sessionManager.activeSession?.frequency, 7.030)
        XCTAssertEqual(sessionManager.selfSpotFrequency, 7.030)

        // And a later hunt still leaves the new own frequency alone
        _ = sessionManager.updateFrequency(7.054, isTuningToSpot: true)
        XCTAssertEqual(sessionManager.selfSpotFrequency, 7.030)
    }

    @MainActor
    func testFirstFrequencySet_BecomesSelfSpotFrequency() {
        // Given: a session started without a frequency
        startPOTASession(frequency: nil)
        XCTAssertNil(sessionManager.selfSpotFrequency)

        // When: the operator sets the frequency, then hunts
        _ = sessionManager.updateFrequency(14.060)
        _ = sessionManager.updateFrequency(14.044, isTuningToSpot: true)

        // Then
        XCTAssertEqual(sessionManager.activeSession?.frequency, 14.044)
        XCTAssertEqual(sessionManager.selfSpotFrequency, 14.060)
    }

    @MainActor
    func testRadioDialChange_FollowsRadio() {
        // Given: CAT-driven changes are the operator's own QSY (frequency
        // follows the radio) — documented behaviour, see CAR-296 report.
        startPOTASession(frequency: 7.000)

        // When
        sessionManager.handleRadioFrequencyChange(7.020)

        // Then
        XCTAssertEqual(sessionManager.activeSession?.frequency, 7.020)
        XCTAssertEqual(sessionManager.selfSpotFrequency, 7.020)
    }

    @MainActor
    func testEndSession_ClearsSelfSpotRecord() {
        // Given
        startPOTASession(frequency: 7.000)
        _ = sessionManager.updateFrequency(7.054, isTuningToSpot: true)
        guard let sessionId = sessionManager.activeSession?.id else {
            return XCTFail("Expected an active session")
        }
        XCTAssertEqual(sessionManager.recordedSelfSpotFrequency(for: sessionId), 7.000)

        // When
        sessionManager.endSession()

        // Then
        XCTAssertNil(sessionManager.selfSpotFrequency)
        XCTAssertNil(sessionManager.recordedSelfSpotFrequency(for: sessionId))
        XCTAssertNil(UserDefaults.standard.object(forKey: "activeLoggingSessionSelfSpotFrequency"))
        XCTAssertNil(UserDefaults.standard.object(forKey: "activeLoggingSessionSelfSpotSessionId"))
    }

    @MainActor
    func testNewSession_DoesNotInheritPreviousRecord() {
        // Given: a session with a recorded own frequency
        startPOTASession(frequency: 7.000)
        _ = sessionManager.updateFrequency(7.054, isTuningToSpot: true)

        // When: starting another session (pauses the first)
        sessionManager.startSession(myCallsign: "N0TEST", mode: "CW", frequency: 14.060)

        // Then: the new session resolves to its own frequency
        XCTAssertEqual(sessionManager.selfSpotFrequency, 14.060)
    }

    @MainActor
    func testSpotFrequency_WithoutRecord_FallsBackToSessionFrequency() {
        // Given: no frequency update has happened since start
        startPOTASession(frequency: 7.000)
        guard let session = sessionManager.activeSession else {
            return XCTFail("Expected an active session")
        }
        XCTAssertNil(sessionManager.recordedSelfSpotFrequency(for: session.id))

        // Then
        XCTAssertEqual(sessionManager.spotFrequency(for: session), 7.000)
        XCTAssertEqual(sessionManager.selfSpotFrequency, 7.000)
    }

    @MainActor
    func testSelfSpotFrequency_NoActiveSession_IsNil() {
        XCTAssertNil(sessionManager.selfSpotFrequency)
    }

    // MARK: Private

    private func clearDefaults() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "activeLoggingSessionId")
        defaults.removeObject(forKey: "activeLoggingSessionSelfSpotFrequency")
        defaults.removeObject(forKey: "activeLoggingSessionSelfSpotSessionId")
        defaults.removeObject(forKey: "potaAutoSpotEnabled")
        defaults.removeObject(forKey: "potaQRTSpotEnabled")
        defaults.removeObject(forKey: "autoRecordConditions")
    }

    @MainActor
    private func startPOTASession(frequency: Double? = 7.000) {
        sessionManager.startSession(
            myCallsign: "N0TEST",
            mode: "CW",
            frequency: frequency,
            activationType: .pota,
            parkReference: "US-0001"
        )
    }
}

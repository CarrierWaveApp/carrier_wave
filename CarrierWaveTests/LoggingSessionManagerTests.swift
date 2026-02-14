// swiftlint:disable file_length type_body_length

import CarrierWaveCore
import SwiftData
import XCTest
@testable import CarrierWave

/// Tests for LoggingSessionManager - the core log management orchestrator
///
/// These tests cover:
/// - Session lifecycle (start, pause, resume, end, delete)
/// - QSO logging with various field combinations
/// - Notes management
/// - Hidden QSO handling
/// - Service presence marking (without network calls)
/// - Metadata mode filtering (WEATHER, SOLAR, NOTE)
final class LoggingSessionManagerTests: XCTestCase {
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var sessionManager: LoggingSessionManager!

    // MARK: - Setup/Teardown

    @MainActor
    override func setUp() async throws {
        let (container, context) = try TestModelContainer.createWithContext()
        modelContainer = container
        modelContext = context
        sessionManager = LoggingSessionManager(modelContext: modelContext)

        // Clear UserDefaults keys used by session manager
        UserDefaults.standard.removeObject(forKey: "activeLoggingSessionId")
    }

    @MainActor
    override func tearDown() async throws {
        // End any active session
        if sessionManager.hasActiveSession {
            sessionManager.endSession()
        }
        UserDefaults.standard.removeObject(forKey: "activeLoggingSessionId")
        sessionManager = nil
        modelContext = nil
        modelContainer = nil
    }

    // MARK: - Session Lifecycle Tests

    @MainActor
    func testStartSession_CreatesActiveSession() {
        // When
        sessionManager.startSession(
            myCallsign: "N0TEST",
            mode: "CW",
            frequency: 14.060,
            activationType: .casual
        )

        // Then
        XCTAssertTrue(sessionManager.hasActiveSession)
        XCTAssertNotNil(sessionManager.activeSession)
        XCTAssertEqual(sessionManager.activeSession?.myCallsign, "N0TEST")
        XCTAssertEqual(sessionManager.activeSession?.mode, "CW")
        XCTAssertEqual(sessionManager.activeSession?.frequency, 14.060)
        XCTAssertEqual(sessionManager.activeSession?.activationType, .casual)
        XCTAssertEqual(sessionManager.activeSession?.status, .active)
    }

    @MainActor
    func testStartSession_POTAActivation() {
        // When
        sessionManager.startSession(
            myCallsign: "N0TEST",
            mode: "SSB",
            frequency: 14.250,
            activationType: .pota,
            parkReference: "US-0001",
            myGrid: "FN31"
        )

        // Then
        XCTAssertEqual(sessionManager.activeSession?.activationType, .pota)
        XCTAssertEqual(sessionManager.activeSession?.parkReference, "US-0001")
        XCTAssertEqual(sessionManager.activeSession?.myGrid, "FN31")
    }

    @MainActor
    func testStartSession_WithEquipment() {
        // When
        sessionManager.startSession(
            myCallsign: "N0TEST",
            mode: "CW",
            frequency: 14.060,
            activationType: .casual,
            myAntenna: "EFHW 49:1",
            myKey: "Begali Traveller",
            myMic: nil,
            extraEquipment: "Battery pack",
            attendees: "KI7QCF"
        )

        // Then
        XCTAssertEqual(sessionManager.activeSession?.myAntenna, "EFHW 49:1")
        XCTAssertEqual(sessionManager.activeSession?.myKey, "Begali Traveller")
        XCTAssertNil(sessionManager.activeSession?.myMic)
        XCTAssertEqual(sessionManager.activeSession?.extraEquipment, "Battery pack")
        XCTAssertEqual(sessionManager.activeSession?.attendees, "KI7QCF")
    }

    @MainActor
    func testStartSession_EndsExistingSession() throws {
        // Given - first session
        sessionManager.startSession(myCallsign: "N0TEST", mode: "CW")
        let firstSessionId = sessionManager.activeSession?.id

        // When - start second session
        sessionManager.startSession(myCallsign: "W1AW", mode: "SSB")

        // Then
        XCTAssertNotEqual(sessionManager.activeSession?.id, firstSessionId)
        XCTAssertEqual(sessionManager.activeSession?.myCallsign, "W1AW")

        // First session should be marked as completed
        let predicate = #Predicate<LoggingSession> { $0.id == firstSessionId! }
        let descriptor = FetchDescriptor<LoggingSession>(predicate: predicate)
        let oldSession = try modelContext.fetch(descriptor).first
        XCTAssertEqual(oldSession?.status, .completed)
    }

    @MainActor
    func testEndSession_SetsCompletedStatus() throws {
        // Given
        sessionManager.startSession(myCallsign: "N0TEST", mode: "CW")
        let sessionId = sessionManager.activeSession?.id

        // When
        sessionManager.endSession()

        // Then
        XCTAssertFalse(sessionManager.hasActiveSession)
        XCTAssertNil(sessionManager.activeSession)

        // Verify session is marked completed in database
        let predicate = #Predicate<LoggingSession> { $0.id == sessionId! }
        let descriptor = FetchDescriptor<LoggingSession>(predicate: predicate)
        let session = try modelContext.fetch(descriptor).first
        XCTAssertEqual(session?.status, .completed)
        XCTAssertNotNil(session?.endedAt)
    }

    @MainActor
    func testPauseAndResumeSession() {
        // Given
        sessionManager.startSession(myCallsign: "N0TEST", mode: "CW")

        // When - pause
        sessionManager.pauseSession()

        // Then
        XCTAssertEqual(sessionManager.activeSession?.status, .paused)

        // When - resume
        sessionManager.resumeSession()

        // Then
        XCTAssertEqual(sessionManager.activeSession?.status, .active)
    }

    @MainActor
    func testDeleteCurrentSession_HidesAllQSOs() throws {
        // Given - session with QSOs
        sessionManager.startSession(myCallsign: "N0TEST", mode: "CW", frequency: 14.060)
        _ = sessionManager.logQSO(callsign: "W1AW")
        _ = sessionManager.logQSO(callsign: "K3LR")
        _ = sessionManager.logQSO(callsign: "N3LLO")

        // When
        sessionManager.deleteCurrentSession()

        // Then
        XCTAssertFalse(sessionManager.hasActiveSession)

        // All QSOs should be hidden
        let qsos = try modelContext.fetch(FetchDescriptor<QSO>())
        XCTAssertEqual(qsos.count, 3)
        XCTAssertTrue(qsos.allSatisfy(\.isHidden))
    }

    // MARK: - QSO Logging Tests

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

    // MARK: - Hidden QSO Tests

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

    // MARK: - Session Query Tests

    @MainActor
    func testGetRecentSessions_ReturnsSessionsInOrder() {
        // Given - create multiple sessions
        sessionManager.startSession(myCallsign: "N0TEST", mode: "CW")
        sessionManager.endSession()

        sessionManager.startSession(myCallsign: "W1AW", mode: "SSB")
        sessionManager.endSession()

        sessionManager.startSession(myCallsign: "K3LR", mode: "FT8")
        sessionManager.endSession()

        // When
        let recentSessions = sessionManager.getRecentSessions(limit: 10)

        // Then
        XCTAssertEqual(recentSessions.count, 3)
        // Most recent first
        XCTAssertEqual(recentSessions[0].myCallsign, "K3LR")
        XCTAssertEqual(recentSessions[1].myCallsign, "W1AW")
        XCTAssertEqual(recentSessions[2].myCallsign, "N0TEST")
    }

    @MainActor
    func testGetRecentSessions_RespectsLimit() {
        // Given - create 5 sessions
        for i in 1 ... 5 {
            sessionManager.startSession(myCallsign: "N\(i)TEST", mode: "CW")
            sessionManager.endSession()
        }

        // When
        let recentSessions = sessionManager.getRecentSessions(limit: 3)

        // Then
        XCTAssertEqual(recentSessions.count, 3)
    }

    // MARK: - Session Title Tests

    @MainActor
    func testUpdateTitle_SetsCustomTitle() {
        // Given
        sessionManager.startSession(myCallsign: "N0TEST", mode: "CW")

        // When
        sessionManager.updateTitle("My Custom Session")

        // Then
        XCTAssertEqual(sessionManager.activeSession?.customTitle, "My Custom Session")
        XCTAssertEqual(sessionManager.activeSession?.displayTitle, "My Custom Session")
    }

    @MainActor
    func testDisplayTitle_FallsBackToDefaultWhenNoCustomTitle() {
        // Given
        sessionManager.startSession(
            myCallsign: "N0TEST",
            mode: "CW",
            activationType: .pota,
            parkReference: "US-0001"
        )

        // Then
        XCTAssertNil(sessionManager.activeSession?.customTitle)
        XCTAssertEqual(sessionManager.activeSession?.displayTitle, "N0TEST at US-0001")
    }
}

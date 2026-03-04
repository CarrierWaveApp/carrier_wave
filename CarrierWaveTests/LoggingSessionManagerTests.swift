import CarrierWaveCore
import CarrierWaveData
import SwiftData
import XCTest
@testable import CarrierWave

/// Tests for LoggingSessionManager - the core log management orchestrator
///
/// These tests cover:
/// - Session lifecycle (start, pause, resume, end, delete)
/// - QSO logging with various field combinations (in +QSOLogging)
/// - Notes management (in +QSOLogging)
/// - Hidden QSO handling (in +HiddenQSOs)
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

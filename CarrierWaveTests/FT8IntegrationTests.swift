import CarrierWaveCore
import SwiftData
import XCTest
@testable import CarrierWave

/// Integration tests validating the end-to-end flow from FT8 decoded messages
/// to QSO creation. Tests drive FT8QSOStateMachine through a complete exchange,
/// then log via LoggingSessionManager — mirroring what FT8SessionManager does.
final class FT8IntegrationTests: XCTestCase {
    // MARK: Internal

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

        UserDefaults.standard.removeObject(forKey: "activeLoggingSessionId")
    }

    @MainActor
    override func tearDown() async throws {
        if sessionManager.hasActiveSession {
            sessionManager.endSession()
        }
        UserDefaults.standard.removeObject(forKey: "activeLoggingSessionId")
        sessionManager = nil
        modelContext = nil
        modelContainer = nil
    }

    // MARK: - Test 1: Complete S&P Exchange Creates QSO with Correct Fields

    @MainActor
    func testFT8QSOCompletion_CreatesQSOWithCorrectFields() throws {
        // Given — start an FT8 session on 20m
        sessionManager.startSession(
            myCallsign: "N0TEST",
            mode: "FT8",
            frequency: 14.074,
            activationType: .casual,
            myGrid: "FN31"
        )

        // Set up state machine for S&P exchange
        var stateMachine = FT8QSOStateMachine(
            myCallsign: "N0TEST",
            myGrid: "FN31"
        )

        // Step 1: Initiate call to a CQ station
        stateMachine.initiateCall(to: "W1AW", theirGrid: "FN42")
        XCTAssertEqual(stateMachine.state, .calling)

        // Step 2: Receive signal report from them
        let reportMsg = FT8Message.signalReport(
            from: "W1AW", to: "N0TEST", dB: -12
        )
        stateMachine.myReport = -5
        stateMachine.processMessage(reportMsg)
        XCTAssertEqual(stateMachine.state, .reportSent)

        // Step 3: Receive RR73 to complete
        let rr73Msg = FT8Message.rogerEnd(from: "W1AW", to: "N0TEST")
        stateMachine.processMessage(rr73Msg)
        XCTAssertEqual(stateMachine.state, .complete)

        // Extract completed QSO and log it (mirroring FT8SessionManager.logCompletedQSO)
        let completed = stateMachine.completedQSO
        XCTAssertNotNil(completed)

        let rstSent = formatReport(completed?.myReport)
        let rstReceived = formatReport(completed?.theirReport)

        let qso = try sessionManager.logQSO(
            callsign: XCTUnwrap(completed?.theirCallsign),
            rstSent: rstSent,
            rstReceived: rstReceived,
            theirGrid: completed?.theirGrid
        )

        // Then — verify all QSO fields
        XCTAssertNotNil(qso)
        XCTAssertEqual(qso?.callsign, "W1AW")
        XCTAssertEqual(qso?.mode, "FT8")
        XCTAssertEqual(qso?.band, "20m")
        XCTAssertEqual(qso?.frequency, 14.074)
        XCTAssertEqual(qso?.myCallsign, "N0TEST")
        XCTAssertEqual(qso?.myGrid, "FN31")
        XCTAssertEqual(qso?.theirGrid, "FN42")
        XCTAssertEqual(qso?.rstSent, "-05")
        XCTAssertEqual(qso?.rstReceived, "-12")
        XCTAssertEqual(qso?.importSource, .logger)
    }

    // MARK: - Test 2: dB Signal Reports Stored Correctly in RST Fields

    @MainActor
    func testFT8SignalReports_StoredCorrectlyAsStrings() throws {
        // Given — start FT8 session
        sessionManager.startSession(
            myCallsign: "N0TEST",
            mode: "FT8",
            frequency: 7.074,
            activationType: .casual,
            myGrid: "FN31"
        )

        // Drive state machine through a complete exchange with specific dB values
        var stateMachine = FT8QSOStateMachine(
            myCallsign: "N0TEST",
            myGrid: "FN31"
        )

        stateMachine.initiateCall(to: "K3LR", theirGrid: "EN91")
        stateMachine.myReport = -19

        // Receive their signal report: -12 dB
        stateMachine.processMessage(
            .signalReport(from: "K3LR", to: "N0TEST", dB: -12)
        )

        // Complete with RR73
        stateMachine.processMessage(
            .rogerEnd(from: "K3LR", to: "N0TEST")
        )

        let completed = try XCTUnwrap(stateMachine.completedQSO)
        XCTAssertEqual(completed.theirReport, -12)
        XCTAssertEqual(completed.myReport, -19)

        // Log via session manager with formatted reports
        let rstSent = formatReport(completed.myReport)
        let rstReceived = formatReport(completed.theirReport)

        // Verify formatted strings before logging
        XCTAssertEqual(rstSent, "-19")
        XCTAssertEqual(rstReceived, "-12")

        let qso = sessionManager.logQSO(
            callsign: completed.theirCallsign,
            rstSent: rstSent,
            rstReceived: rstReceived,
            theirGrid: completed.theirGrid
        )

        // Then — verify negative dB values stored correctly
        XCTAssertNotNil(qso)
        XCTAssertEqual(qso?.rstSent, "-19")
        XCTAssertEqual(qso?.rstReceived, "-12")

        // Also verify positive values format correctly
        XCTAssertEqual(formatReport(5), "+05")
        XCTAssertEqual(formatReport(0), "+00")
        XCTAssertEqual(formatReport(nil), "+00")
    }

    // MARK: - Test 3: POTA Activation Auto-Applies Park Reference

    @MainActor
    func testPOTAActivation_FT8QSOHasParkReference() throws {
        // Given — start a POTA activation session with FT8
        sessionManager.startSession(
            myCallsign: "N0TEST",
            mode: "FT8",
            frequency: 14.074,
            activationType: .pota,
            parkReference: "US-0001",
            myGrid: "FN31"
        )

        // Drive state machine through complete S&P exchange
        var stateMachine = FT8QSOStateMachine(
            myCallsign: "N0TEST",
            myGrid: "FN31"
        )

        stateMachine.initiateCall(to: "N3LLO", theirGrid: "FM19")
        stateMachine.myReport = -8

        stateMachine.processMessage(
            .signalReport(from: "N3LLO", to: "N0TEST", dB: -15)
        )
        stateMachine.processMessage(
            .rogerEnd(from: "N3LLO", to: "N0TEST")
        )

        XCTAssertEqual(stateMachine.state, .complete)

        let completed = try XCTUnwrap(stateMachine.completedQSO)
        let qso = sessionManager.logQSO(
            callsign: completed.theirCallsign,
            rstSent: formatReport(completed.myReport),
            rstReceived: formatReport(completed.theirReport),
            theirGrid: completed.theirGrid
        )

        // Then — QSO inherits park reference from POTA session
        XCTAssertNotNil(qso)
        XCTAssertEqual(qso?.parkReference, "US-0001")
        XCTAssertEqual(qso?.callsign, "N3LLO")
        XCTAssertEqual(qso?.mode, "FT8")
        XCTAssertEqual(qso?.theirGrid, "FM19")
        XCTAssertEqual(qso?.rstSent, "-08")
        XCTAssertEqual(qso?.rstReceived, "-15")
    }

    // MARK: Private

    // MARK: - Helpers

    /// Formats an FT8 dB report to string (mirrors FT8SessionManager.formatReport)
    private func formatReport(_ report: Int?) -> String {
        guard let report else {
            return "+00"
        }
        let sign = report >= 0 ? "+" : "-"
        return "\(sign)\(String(format: "%02d", abs(report)))"
    }
}

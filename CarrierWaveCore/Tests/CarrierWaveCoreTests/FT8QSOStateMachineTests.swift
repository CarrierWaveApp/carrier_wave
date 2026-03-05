//
//  FT8QSOStateMachineTests.swift
//  CarrierWaveCore
//

import Testing
@testable import CarrierWaveCore

@Suite("FT8 QSO State Machine Tests")
struct FT8QSOStateMachineTests {
    let myCall = "K1ABC"
    let myGrid = "FN42"

    // MARK: - Search & Pounce Flow

    @Test("S&P: idle -> calling on CQ tap")
    func spCallingOnCQTap() {
        var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
        #expect(sm.state == .idle)

        sm.initiateCall(to: "W9XYZ", theirGrid: "EN37")
        #expect(sm.state == .calling)
        #expect(sm.theirCallsign == "W9XYZ")
        #expect(sm.nextTXMessage == "W9XYZ \(myCall) \(myGrid)")
    }

    @Test("S&P: calling -> reportSent on signal report received")
    func spReportSent() {
        var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
        sm.initiateCall(to: "W9XYZ", theirGrid: "EN37")

        sm.processMessage(.signalReport(from: "W9XYZ", to: myCall, dB: -12))
        #expect(sm.state == .reportSent)
        #expect(sm.theirReport == -12)
    }

    @Test("S&P: reportSent -> completing on RR73 received")
    func spCompleteOnRR73() {
        var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
        sm.initiateCall(to: "W9XYZ", theirGrid: "EN37")
        sm.processMessage(.signalReport(from: "W9XYZ", to: myCall, dB: -12))
        sm.processMessage(.rogerEnd(from: "W9XYZ", to: myCall))
        #expect(sm.state == .completing)
    }

    // MARK: - CQ (Run) Flow

    @Test("CQ: idle generates CQ message")
    func cqIdleGeneratesCQ() {
        var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
        sm.setCQMode(modifier: nil)
        #expect(sm.nextTXMessage == "CQ \(myCall) \(myGrid)")
    }

    @Test("CQ POTA: includes modifier")
    func cqPotaIncludesModifier() {
        var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
        sm.setCQMode(modifier: "POTA")
        #expect(sm.nextTXMessage == "CQ POTA \(myCall) \(myGrid)")
    }

    @Test("CQ: station responds -> exchange starts")
    func cqStationResponds() {
        var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
        sm.setCQMode(modifier: nil)
        sm.processMessage(.directed(from: "W9XYZ", to: myCall, grid: "EN37"))
        #expect(sm.state == .reportSent)
        #expect(sm.theirCallsign == "W9XYZ")
    }

    // MARK: - Timeout

    @Test("Timeout after N cycles with no response")
    func timeoutAfterNCycles() {
        var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
        sm.initiateCall(to: "W9XYZ", theirGrid: "EN37")
        #expect(sm.state == .calling)

        // Simulate 10 cycles with no response
        for _ in 0 ..< 10 {
            sm.advanceCycle()
        }
        #expect(sm.state == .idle, "Should timeout and return to idle")
    }

    // MARK: - Duplicate Prevention

    @Test("Won't initiate QSO with already-worked station")
    func duplicatePrevention() {
        var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
        sm.markWorked("W9XYZ")
        sm.initiateCall(to: "W9XYZ", theirGrid: "EN37")
        #expect(sm.state == .idle, "Should not start QSO with worked station")
    }

    // MARK: - Completed QSO Data

    @Test("Completed QSO provides all fields (available in completing state)")
    func completedQSOData() {
        var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
        sm.initiateCall(to: "W9XYZ", theirGrid: "EN37")
        sm.processMessage(.signalReport(from: "W9XYZ", to: myCall, dB: -12))
        sm.myReport = -7
        sm.processMessage(.rogerEnd(from: "W9XYZ", to: myCall))
        #expect(sm.state == .completing)

        let qso = sm.completedQSO
        #expect(qso != nil)
        #expect(qso?.theirCallsign == "W9XYZ")
        #expect(qso?.theirGrid == "EN37")
        #expect(qso?.theirReport == -12)
        #expect(qso?.myReport == -7)
    }

    // MARK: - TX Message Format

    @Test("reportSent TX message formats negative dB correctly")
    func reportSentNegativeDB() {
        var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
        sm.initiateCall(to: "W9XYZ", theirGrid: "EN37")
        sm.processMessage(.signalReport(from: "W9XYZ", to: myCall, dB: -12))
        sm.myReport = -7
        #expect(sm.nextTXMessage == "W9XYZ \(myCall) R-07")
    }

    @Test("reportSent TX message formats positive dB correctly")
    func reportSentPositiveDB() {
        var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
        sm.initiateCall(to: "W9XYZ", theirGrid: "EN37")
        sm.processMessage(.signalReport(from: "W9XYZ", to: myCall, dB: -12))
        sm.myReport = 5
        #expect(sm.nextTXMessage == "W9XYZ \(myCall) R+05")
    }

    // MARK: - Role Tracking

    @Test("S&P: role is searchAndPounce after initiateCall")
    func spRoleTracking() {
        var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
        sm.initiateCall(to: "W9XYZ", theirGrid: "EN37")
        #expect(sm.role == .searchAndPounce)
    }

    @Test("CQ: role is cqOriginator when station responds to our CQ")
    func cqRoleTracking() {
        var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
        sm.setCQMode(modifier: nil)
        sm.processMessage(.directed(from: "W9XYZ", to: myCall, grid: "EN37"))
        #expect(sm.role == .cqOriginator)
    }

    @Test("S&P: reportSent TX message has R-prefix")
    func spReportSentHasRPrefix() {
        var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
        sm.initiateCall(to: "W9XYZ", theirGrid: "EN37")
        sm.processMessage(.signalReport(from: "W9XYZ", to: myCall, dB: -12))
        sm.myReport = -7
        #expect(sm.nextTXMessage == "W9XYZ \(myCall) R-07")
    }

    @Test("S&P: reportSent TX message has R-prefix for positive dB")
    func spReportSentRPrefixPositive() {
        var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
        sm.initiateCall(to: "W9XYZ", theirGrid: "EN37")
        sm.processMessage(.signalReport(from: "W9XYZ", to: myCall, dB: -12))
        sm.myReport = 5
        #expect(sm.nextTXMessage == "W9XYZ \(myCall) R+05")
    }

    @Test("CQ: reportSent TX message has NO R-prefix")
    func cqReportSentNoRPrefix() {
        var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
        sm.setCQMode(modifier: nil)
        sm.processMessage(.directed(from: "W9XYZ", to: myCall, grid: "EN37"))
        sm.myReport = -3
        #expect(sm.nextTXMessage == "W9XYZ \(myCall) -03")
    }

    @Test("Role resets to nil on resetForNextQSO")
    func roleResetsOnReset() {
        var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
        sm.initiateCall(to: "W9XYZ", theirGrid: "EN37")
        #expect(sm.role == .searchAndPounce)
        sm.resetForNextQSO()
        #expect(sm.role == nil)
    }

    // MARK: - Completing State

    @Test("CQ: QSO completes immediately when receiving R+report (enters completing)")
    func cqCompletesOnRogerReport() {
        var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
        sm.setCQMode(modifier: nil)
        sm.processMessage(.directed(from: "W9XYZ", to: myCall, grid: "EN37"))
        sm.myReport = -3
        sm.processMessage(.rogerReport(from: "W9XYZ", to: myCall, dB: 2))
        #expect(sm.state == .completing)
        #expect(sm.completedQSO != nil)
    }

    @Test("S&P: QSO completes when receiving RR73 (enters completing)")
    func spCompletesOnRR73Completing() {
        var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
        sm.initiateCall(to: "W9XYZ", theirGrid: "EN37")
        sm.processMessage(.signalReport(from: "W9XYZ", to: myCall, dB: -12))
        sm.myReport = -7
        sm.processMessage(.rogerEnd(from: "W9XYZ", to: myCall))
        #expect(sm.state == .completing)
        #expect(sm.completedQSO != nil)
    }

    @Test("Completing state returns to idle after one advanceCycle")
    func completingReturnsToIdle() {
        var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
        sm.initiateCall(to: "W9XYZ", theirGrid: "EN37")
        sm.processMessage(.signalReport(from: "W9XYZ", to: myCall, dB: -12))
        sm.processMessage(.rogerEnd(from: "W9XYZ", to: myCall))
        #expect(sm.state == .completing)
        sm.advanceCycle()
        #expect(sm.state == .idle)
    }

    @Test("CQ: completing TX message is RR73 for CQ originator")
    func cqCompletingSendsRR73() {
        var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
        sm.setCQMode(modifier: nil)
        sm.processMessage(.directed(from: "W9XYZ", to: myCall, grid: "EN37"))
        sm.myReport = -3
        sm.processMessage(.rogerReport(from: "W9XYZ", to: myCall, dB: 2))
        #expect(sm.nextTXMessage == "W9XYZ \(myCall) RR73")
    }

    @Test("S&P: completing TX message is 73")
    func spCompletingSends73() {
        var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
        sm.initiateCall(to: "W9XYZ", theirGrid: "EN37")
        sm.processMessage(.signalReport(from: "W9XYZ", to: myCall, dB: -12))
        sm.processMessage(.rogerEnd(from: "W9XYZ", to: myCall))
        #expect(sm.nextTXMessage == "W9XYZ \(myCall) 73")
    }

    @Test("S&P timeout reduced to 4 cycles")
    func spTimeoutReducedTo4Cycles() {
        var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
        sm.initiateCall(to: "W9XYZ", theirGrid: "EN37")
        for _ in 0 ..< 4 {
            sm.advanceCycle()
        }
        #expect(sm.state == .idle, "S&P should timeout after 4 cycles")
    }

    // MARK: - CQ Duplicate Prevention

    @Test("CQ mode skips already-worked station")
    func cqSkipsWorkedStation() {
        var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
        sm.setCQMode(modifier: nil)
        sm.markWorked("W9XYZ")
        sm.processMessage(.directed(from: "W9XYZ", to: myCall, grid: "EN37"))
        #expect(sm.state == .idle, "Should not start QSO with worked station in CQ mode")
    }

    // MARK: - Third-Party Messages

    @Test("Third-party message does not reset timeout counter")
    func thirdPartyDoesNotResetTimeout() {
        var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
        sm.initiateCall(to: "W9XYZ", theirGrid: "EN37")

        // Advance 7 cycles (one short of timeout)
        for _ in 0 ..< 7 {
            sm.advanceCycle()
        }
        // A different station calls us — should NOT reset timeout
        sm.processMessage(.signalReport(from: "AA1BB", to: myCall, dB: -5))
        sm.advanceCycle()
        #expect(sm.state == .idle, "Third-party message should not prevent timeout")
    }

    // MARK: - Timeout Field Reset

    @Test("Timeout resets QSO fields")
    func timeoutResetsFields() {
        var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
        sm.initiateCall(to: "W9XYZ", theirGrid: "EN37")

        for _ in 0 ..< 10 {
            sm.advanceCycle()
        }
        #expect(sm.theirCallsign == nil)
        #expect(sm.theirGrid == nil)
        #expect(sm.theirReport == nil)
    }

    // MARK: - RR73 State Restrictions

    @Test("RR73 from calling state does not complete QSO")
    func rr73FromCallingIgnored() {
        var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
        sm.initiateCall(to: "W9XYZ", theirGrid: "EN37")
        sm.processMessage(.rogerEnd(from: "W9XYZ", to: myCall))
        #expect(sm.state == .calling, "RR73 in calling state should be ignored")
    }

    // MARK: - Irrelevant Messages

    @Test("Ignores messages not directed at us")
    func ignoresIrrelevant() {
        var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
        sm.initiateCall(to: "W9XYZ", theirGrid: "EN37")

        // Message between other stations
        sm.processMessage(.signalReport(from: "AA1BB", to: "CC2DD", dB: -5))
        #expect(sm.state == .calling, "Should ignore messages not for us")
    }

    // MARK: - completedQSO Invariant

    @Test("completedQSO returns nil when not complete")
    func completedQSONilBeforeComplete() {
        var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
        sm.initiateCall(to: "W9XYZ", theirGrid: "EN37")
        #expect(sm.completedQSO == nil)
    }
}

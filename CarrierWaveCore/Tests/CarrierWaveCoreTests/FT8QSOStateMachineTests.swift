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

    @Test("S&P: reportSent -> complete on RR73 received")
    func spCompleteOnRR73() {
        var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
        sm.initiateCall(to: "W9XYZ", theirGrid: "EN37")
        sm.processMessage(.signalReport(from: "W9XYZ", to: myCall, dB: -12))
        sm.processMessage(.rogerEnd(from: "W9XYZ", to: myCall))
        #expect(sm.state == .complete)
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

    @Test("Completed QSO provides all fields")
    func completedQSOData() {
        var sm = FT8QSOStateMachine(myCallsign: myCall, myGrid: myGrid)
        sm.initiateCall(to: "W9XYZ", theirGrid: "EN37")
        sm.processMessage(.signalReport(from: "W9XYZ", to: myCall, dB: -12))
        sm.myReport = -7
        sm.processMessage(.rogerEnd(from: "W9XYZ", to: myCall))

        let qso = sm.completedQSO
        #expect(qso != nil)
        #expect(qso?.theirCallsign == "W9XYZ")
        #expect(qso?.theirGrid == "EN37")
        #expect(qso?.theirReport == -12)
        #expect(qso?.myReport == -7)
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
}

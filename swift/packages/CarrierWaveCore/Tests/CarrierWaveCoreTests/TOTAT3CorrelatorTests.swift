//
//  TOTAT3CorrelatorTests.swift
//  CarrierWaveCoreTests
//

import Foundation
import Testing
@testable import CarrierWaveCore

struct TOTAT3CorrelatorTests {
    // MARK: Internal

    @Test("Spot precedes QSO within window → match")
    func spotWithinWindow() {
        let qsoTime = Date(timeIntervalSince1970: 1_700_000_000)
        let qso = makeQSO(callsign: "K1ABC", at: qsoTime)
        let spot = T3SpotRecord(
            callsign: "K1ABC",
            maidenheadTile: "EM84tt",
            createdAt: qsoTime.addingTimeInterval(-3_600) // 1h before QSO
        )
        let matches = TOTAT3Correlator.correlate(spots: [spot], qsos: [qso])
        #expect(matches.count == 1)
        #expect(matches.first?.theirTile == "EM84tt")
    }

    @Test("Spot beyond 6h window → no match")
    func spotBeyondWindow() {
        let qsoTime = Date(timeIntervalSince1970: 1_700_000_000)
        let qso = makeQSO(callsign: "K1ABC", at: qsoTime)
        let spot = T3SpotRecord(
            callsign: "K1ABC",
            maidenheadTile: "EM84tt",
            createdAt: qsoTime.addingTimeInterval(-7 * 3_600) // 7h before QSO
        )
        let matches = TOTAT3Correlator.correlate(spots: [spot], qsos: [qso])
        #expect(matches.isEmpty)
    }

    @Test("Spot follows QSO → no match")
    func spotAfterQSO() {
        let qsoTime = Date(timeIntervalSince1970: 1_700_000_000)
        let qso = makeQSO(callsign: "K1ABC", at: qsoTime)
        let spot = T3SpotRecord(
            callsign: "K1ABC",
            maidenheadTile: "EM84tt",
            createdAt: qsoTime.addingTimeInterval(3_600) // 1h after QSO
        )
        let matches = TOTAT3Correlator.correlate(spots: [spot], qsos: [qso])
        #expect(matches.isEmpty)
    }

    @Test("Multiple matching spots → take closest preceding")
    func closestPrecedingWins() {
        let qsoTime = Date(timeIntervalSince1970: 1_700_000_000)
        let qso = makeQSO(callsign: "K1ABC", at: qsoTime)
        let early = T3SpotRecord(
            callsign: "K1ABC",
            maidenheadTile: "EM84aa",
            createdAt: qsoTime.addingTimeInterval(-5 * 3_600)
        )
        let late = T3SpotRecord(
            callsign: "K1ABC",
            maidenheadTile: "EM84bb",
            createdAt: qsoTime.addingTimeInterval(-1 * 3_600)
        )
        let matches = TOTAT3Correlator.correlate(spots: [early, late], qsos: [qso])
        #expect(matches.count == 1)
        #expect(matches.first?.theirTile == "EM84bb")
    }

    @Test("Spot without maidenheadTile is not a T3 candidate")
    func spotWithoutTile() {
        let qsoTime = Date(timeIntervalSince1970: 1_700_000_000)
        let qso = makeQSO(callsign: "K1ABC", at: qsoTime)
        let spot = T3SpotRecord(
            callsign: "K1ABC",
            maidenheadTile: nil,
            createdAt: qsoTime.addingTimeInterval(-1_800)
        )
        let matches = TOTAT3Correlator.correlate(spots: [spot], qsos: [qso])
        #expect(matches.isEmpty)
    }

    @Test("Callsign matching is case-insensitive")
    func callsignCaseInsensitive() {
        let qsoTime = Date(timeIntervalSince1970: 1_700_000_000)
        let qso = makeQSO(callsign: "k1abc", at: qsoTime)
        let spot = T3SpotRecord(
            callsign: "K1ABC",
            maidenheadTile: "EM84tt",
            createdAt: qsoTime.addingTimeInterval(-1_800)
        )
        let matches = TOTAT3Correlator.correlate(spots: [spot], qsos: [qso])
        #expect(matches.count == 1)
    }

    @Test("Spot for different callsign is not matched")
    func differentCallsignNoMatch() {
        let qsoTime = Date(timeIntervalSince1970: 1_700_000_000)
        let qso = makeQSO(callsign: "K1ABC", at: qsoTime)
        let spot = T3SpotRecord(
            callsign: "N4XYZ",
            maidenheadTile: "EM84tt",
            createdAt: qsoTime.addingTimeInterval(-1_800)
        )
        let matches = TOTAT3Correlator.correlate(spots: [spot], qsos: [qso])
        #expect(matches.isEmpty)
    }

    @Test("Empty spots → no matches")
    func emptySpots() {
        let qso = makeQSO(callsign: "K1ABC", at: Date())
        let matches = TOTAT3Correlator.correlate(spots: [], qsos: [qso])
        #expect(matches.isEmpty)
    }

    @Test("Empty QSOs → no matches")
    func emptyQSOs() {
        let spot = T3SpotRecord(callsign: "K1ABC", maidenheadTile: "EM84tt", createdAt: Date())
        let matches = TOTAT3Correlator.correlate(spots: [spot], qsos: [])
        #expect(matches.isEmpty)
    }

    // MARK: Private

    private func makeQSO(callsign: String, at: Date) -> TOTAScoringQSO {
        TOTAScoringQSO(id: UUID(), mode: "CW", callsign: callsign, timestamp: at)
    }
}

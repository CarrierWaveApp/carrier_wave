//
//  TOTAScoringEngineTests.swift
//  CarrierWaveCoreTests
//
//  Replicates the rules' worked example exactly + variants for QRP, Mobile,
//  FT8 weighting, T3, defensive WL/APRS/VARAC exclusion, PEF, and bonus stack.
//

import Foundation
import Testing
@testable import CarrierWaveCore

// MARK: - TOTAScoringEngineTests

struct TOTAScoringEngineTests {
    // MARK: Internal

    @Test("Rules' worked example: EM73wt, 96.8 pts")
    func rulesWorkedExample() {
        // From TOTA_Rules.pdf: 12 effective QSOs, 5.17 mi, January (winter),
        // 5 lb ruck, dog, first-in-quarter (server-Pending, not in pre-upload
        // total), 191 ft elevation gain (under 200, so no elevation bonus),
        // 10 P2P digital VarAC + 1 SSB + 1 FM repeater. All > 10W. No T3.
        // Expected: 96.8 pts (96.856).
        //
        // Note: rules add the 10-pt first-in-quarter to reach 96.8. In our
        // ledger that bonus is Pending (server-confirmed), so the in-app
        // pre-upload total is the rules' 96.8 minus 10 = 86.856.
        let qsos = (0 ..< 12).map { i in
            TOTAScoringQSO(
                id: UUID(),
                mode: i < 10 ? "VARAC" : (i == 10 ? "SSB" : "FM"),
                callsign: "K\(i)ABC",
                timestamp: Date(timeIntervalSince1970: 1_700_000_000 + Double(i) * 60)
            )
        }
        // VarAC was sent (so the 10 VARAC QSOs would normally drop). The rules'
        // example treats them as 10 P2P QSOs counted at 1× each AND awards a
        // single +5 VarAC bonus. To replicate exactly, we don't tick the
        // session-level varacSent flag here (which would defensively exclude).
        let inputs = TOTAScoringInputs(
            category: .standard,
            qsos: qsos,
            t3CallsignToTile: [:],
            distanceMiles: 5.17,
            elevationGainFeet: 191,
            ruckWeightPounds: 5,
            personalEffortFactor: nil,
            qrpActivation: false,
            isWinter: true,
            withPets: true,
            withKids: false,
            winlinkSent: false,
            aprsSent: false,
            varacSent: false,
            firstActivationOfTileEver: false,
            tileCount: 1
        )
        let result = TOTAScoringEngine.score(inputs)
        // Confirmed subtotal = base 62.04 + winter 12.408 + ruck 3.102 + pets 9.306 = 86.856
        #expect(abs(result.confirmed.qsoSubtotal - 62.04) < 0.01)
        #expect(abs(result.confirmed.subtotal - 86.856) < 0.01)
        #expect(abs(result.total - 86.856) < 0.01)
        // Pending: per-tile +10
        #expect(result.pendingMaxPoints == 10.0)
    }

    @Test("FT8 mode contributes 0.2 per QSO")
    func ft8ModeWeight() {
        let qsos = (0 ..< 5).map { i in
            TOTAScoringQSO(
                id: UUID(),
                mode: "FT8",
                callsign: "K\(i)ABC",
                timestamp: Date()
            )
        }
        let inputs = baseInputs(qsos: qsos, distance: 1.0)
        let result = TOTAScoringEngine.score(inputs)
        // 5 × 0.2 = 1 effective; × 1 mi distance = 1 base
        #expect(abs(result.confirmed.effectiveQSOs - 1.0) < 0.001)
        #expect(abs(result.confirmed.base - 1.0) < 0.001)
    }

    @Test("FT4 weighted same as FT8")
    func ft4WeightedAsFT8() {
        let qsos = (0 ..< 5).map { _ in qso("FT4") }
        let inputs = baseInputs(qsos: qsos, distance: 1.0)
        let result = TOTAScoringEngine.score(inputs)
        #expect(abs(result.confirmed.effectiveQSOs - 1.0) < 0.001)
    }

    @Test("QRP doubles QSO subtotal")
    func qrpDoublesSubtotal() {
        let qsos = (0 ..< 10).map { _ in qso("CW") }
        var inputs = baseInputs(qsos: qsos, distance: 2.0)
        inputs = withQRP(inputs)
        let result = TOTAScoringEngine.score(inputs)
        // 10 × 2 = 20 base, × 2 QRP = 40 qsoSubtotal
        #expect(abs(result.confirmed.qsoSubtotal - 40.0) < 0.001)
        #expect(result.confirmed.qrpMultiplierApplied)
    }

    @Test("T3 boost applies after mode weight")
    func t3BoostAfterModeWeight() {
        let ft8 = TOTAScoringQSO(id: UUID(), mode: "FT8", callsign: "T3STN", timestamp: Date())
        let cw = TOTAScoringQSO(id: UUID(), mode: "CW", callsign: "CWSTN", timestamp: Date())
        let inputs = TOTAScoringInputs(
            category: .standard,
            qsos: [ft8, cw],
            t3CallsignToTile: ["T3STN": "EM84tt", "CWSTN": "EM84uu"],
            distanceMiles: 1.0,
            elevationGainFeet: nil,
            ruckWeightPounds: nil,
            personalEffortFactor: nil,
            qrpActivation: false,
            isWinter: false,
            withPets: false,
            withKids: false,
            winlinkSent: false,
            aprsSent: false,
            varacSent: false,
            firstActivationOfTileEver: false,
            tileCount: 1
        )
        let result = TOTAScoringEngine.score(inputs)
        // FT8 T3 = 0.4, CW T3 = 2.0 → effective 2.4
        #expect(abs(result.confirmed.effectiveQSOs - 2.4) < 0.001)
        // T3 boost = adds the original mode weight (FT8 0.2 + CW 1.0 = 1.2)
        // worth of points × distance × QRP × percentageMultiplier
        #expect(abs(result.estimatedT3Boost - 1.2) < 0.001)
    }

    @Test("Defensive WL/APRS/VARAC exclusion when flag set")
    func defensiveExclusion() {
        let qsos = [
            qso("WINLINK"),
            qso("APRS"),
            qso("VARAC"),
            qso("CW"),
        ]
        var inputs = baseInputs(qsos: qsos, distance: 1.0)
        inputs = withFlats(inputs, winlink: true, aprs: true, varac: true)
        let result = TOTAScoringEngine.score(inputs)
        // Only the CW QSO contributes → 1 effective
        #expect(abs(result.confirmed.effectiveQSOs - 1.0) < 0.001)
        // Flats sum: 5+5+5 = 15 added to subtotal
        #expect(result.confirmed.winlinkFlat == 5)
        #expect(result.confirmed.aprsFlat == 5)
        #expect(result.confirmed.varacFlat == 5)
    }

    @Test("PEF scales the distance term")
    func pefScalesDistance() {
        let qsos = (0 ..< 5).map { _ in qso("CW") }
        var inputs = baseInputs(qsos: qsos, distance: 2.0)
        inputs = withPEF(inputs, factor: 4)
        let result = TOTAScoringEngine.score(inputs)
        // distance 2 × PEF 4 = 8 effective; 5 QSOs × 8 = 40 base
        #expect(abs(result.confirmed.distanceMiles - 8.0) < 0.001)
        #expect(abs(result.confirmed.base - 40.0) < 0.001)
    }

    @Test("Distance floor of 0.25 mi when raw is 0 < d < 0.25")
    func distanceFloorApplied() {
        let qsos = [qso("CW")]
        let inputs = baseInputs(qsos: qsos, distance: 0.1)
        let result = TOTAScoringEngine.score(inputs)
        #expect(abs(result.confirmed.distanceMiles - 0.25) < 0.001)
    }

    @Test("Zero distance disqualifies (no base)")
    func zeroDistanceDisqualifies() {
        let qsos = (0 ..< 10).map { _ in qso("CW") }
        let inputs = baseInputs(qsos: qsos, distance: 0)
        let result = TOTAScoringEngine.score(inputs)
        #expect(result.confirmed.base == 0)
    }

    @Test("Mobile category: no distance/percentage bonuses")
    func mobileCategory() {
        let qsos = (0 ..< 10).map { _ in qso("CW") }
        var inputs = baseInputs(qsos: qsos, distance: 5.0)
        inputs = withWinter(inputs)
        inputs = withCategory(inputs, .mobile)
        let result = TOTAScoringEngine.score(inputs)
        // 10 effective × 1 (no QRP) = 10 qsoSubtotal; no winter bonus
        #expect(result.confirmed.qsoSubtotal == 10)
        #expect(result.confirmed.winterBonus == 0)
        #expect(result.confirmed.subtotal == 10)
    }

    @Test("Mobile: T3 still doubles QSO weight")
    func mobileT3Boost() {
        let qsos = (0 ..< 5).map { i in
            TOTAScoringQSO(id: UUID(), mode: "CW", callsign: "K\(i)", timestamp: Date())
        }
        var inputs = baseInputs(qsos: qsos, distance: 5.0)
        inputs = withCategory(inputs, .mobile)
        var t3: [String: String] = [:]
        for i in 0 ..< 2 {
            t3["K\(i)"] = "EM84xx"
        }
        let withT3 = TOTAScoringInputs(
            category: .mobile,
            qsos: inputs.qsos,
            t3CallsignToTile: t3,
            distanceMiles: inputs.distanceMiles,
            elevationGainFeet: inputs.elevationGainFeet,
            ruckWeightPounds: inputs.ruckWeightPounds,
            personalEffortFactor: inputs.personalEffortFactor,
            qrpActivation: inputs.qrpActivation,
            isWinter: inputs.isWinter,
            withPets: inputs.withPets,
            withKids: inputs.withKids,
            winlinkSent: inputs.winlinkSent,
            aprsSent: inputs.aprsSent,
            varacSent: inputs.varacSent,
            firstActivationOfTileEver: inputs.firstActivationOfTileEver,
            tileCount: inputs.tileCount
        )
        let result = TOTAScoringEngine.score(withT3)
        // 3 normal (1×) + 2 T3 (2×) = 7 effective
        #expect(abs(result.confirmed.effectiveQSOs - 7.0) < 0.001)
        // Mobile t3 boost = 2 (one per T3 QSO; CW weight 1)
        #expect(abs(result.estimatedT3Boost - 2.0) < 0.001)
    }

    @Test("Asserted first-ever-tile adds 10 to total")
    func assertedFirstEver() {
        let qsos = [qso("CW")]
        var inputs = baseInputs(qsos: qsos, distance: 1.0)
        inputs = withFirstEver(inputs)
        let result = TOTAScoringEngine.score(inputs)
        #expect(result.assertedFirstEver == 10)
        #expect(result.total >= 10)
    }

    @Test("Pending max scales with tile count")
    func pendingMaxPerTile() {
        let qsos = [qso("CW")]
        var inputs = baseInputs(qsos: qsos, distance: 1.0)
        inputs = withTileCount(inputs, 3)
        let result = TOTAScoringEngine.score(inputs)
        #expect(result.pendingMaxPoints == 30)
    }

    @Test("Pre-upload total never includes pending bonuses")
    func pendingExcludedFromTotal() {
        let qsos = [qso("CW")]
        var inputs = baseInputs(qsos: qsos, distance: 1.0)
        inputs = withTileCount(inputs, 5)
        let result = TOTAScoringEngine.score(inputs)
        // total should equal confirmed.subtotal + estimated + asserted; not include pendingMax
        let expected = result.confirmed.subtotal + result.estimatedT3Boost + result.assertedFirstEver
        #expect(abs(result.total - expected) < 0.001)
    }

    // MARK: Private

    private func qso(_ mode: String) -> TOTAScoringQSO {
        TOTAScoringQSO(id: UUID(), mode: mode, callsign: "K1ABC", timestamp: Date())
    }

    private func baseInputs(qsos: [TOTAScoringQSO], distance: Double) -> TOTAScoringInputs {
        TOTAScoringInputs(
            category: .standard,
            qsos: qsos,
            t3CallsignToTile: [:],
            distanceMiles: distance,
            elevationGainFeet: nil,
            ruckWeightPounds: nil,
            personalEffortFactor: nil,
            qrpActivation: false,
            isWinter: false,
            withPets: false,
            withKids: false,
            winlinkSent: false,
            aprsSent: false,
            varacSent: false,
            firstActivationOfTileEver: false,
            tileCount: 1
        )
    }

    private func withQRP(_ inputs: TOTAScoringInputs) -> TOTAScoringInputs {
        copy(inputs, qrp: true)
    }

    private func withWinter(_ inputs: TOTAScoringInputs) -> TOTAScoringInputs {
        copy(inputs, winter: true)
    }

    private func withFirstEver(_ inputs: TOTAScoringInputs) -> TOTAScoringInputs {
        copy(inputs, firstEver: true)
    }

    private func withCategory(
        _ inputs: TOTAScoringInputs, _ category: TOTACategoryKind
    ) -> TOTAScoringInputs {
        copy(inputs, category: category)
    }

    private func withPEF(_ inputs: TOTAScoringInputs, factor: Int) -> TOTAScoringInputs {
        copy(inputs, pef: factor)
    }

    private func withTileCount(_ inputs: TOTAScoringInputs, _ count: Int) -> TOTAScoringInputs {
        copy(inputs, tileCount: count)
    }

    private func withFlats(
        _ inputs: TOTAScoringInputs, winlink: Bool, aprs: Bool, varac: Bool
    ) -> TOTAScoringInputs {
        copy(inputs, winlink: winlink, aprs: aprs, varac: varac)
    }

    private func copy(
        _ inputs: TOTAScoringInputs,
        category: TOTACategoryKind? = nil,
        qrp: Bool? = nil,
        winter: Bool? = nil,
        firstEver: Bool? = nil,
        pef: Int? = nil,
        tileCount: Int? = nil,
        winlink: Bool? = nil,
        aprs: Bool? = nil,
        varac: Bool? = nil
    ) -> TOTAScoringInputs {
        TOTAScoringInputs(
            category: category ?? inputs.category,
            qsos: inputs.qsos,
            t3CallsignToTile: inputs.t3CallsignToTile,
            distanceMiles: inputs.distanceMiles,
            elevationGainFeet: inputs.elevationGainFeet,
            ruckWeightPounds: inputs.ruckWeightPounds,
            personalEffortFactor: pef ?? inputs.personalEffortFactor,
            qrpActivation: qrp ?? inputs.qrpActivation,
            isWinter: winter ?? inputs.isWinter,
            withPets: inputs.withPets,
            withKids: inputs.withKids,
            winlinkSent: winlink ?? inputs.winlinkSent,
            aprsSent: aprs ?? inputs.aprsSent,
            varacSent: varac ?? inputs.varacSent,
            firstActivationOfTileEver: firstEver ?? inputs.firstActivationOfTileEver,
            tileCount: tileCount ?? inputs.tileCount
        )
    }
}

//
//  FT8EnrichedDecodeTests.swift
//  CarrierWaveCoreTests
//

import Testing
@testable import CarrierWaveCore

@Suite("FT8EnrichedDecode Tests")
struct FT8EnrichedDecodeTests {
    // MARK: Internal

    // MARK: - Section Classification

    @Test("CQ decode is classified as callingCQ section")
    func cqDecodeSection() {
        let enriched = makeEnriched()
        #expect(enriched.section == .callingCQ)
    }

    @Test("Message directed at me is classified as directedAtYou section")
    func directedAtMeSection() {
        let decode = makeDecode(
            message: .signalReport(from: "K1ABC", to: "W1AW", dB: -11),
            rawText: "W1AW K1ABC -11"
        )
        let enriched = makeEnriched(decode: decode, isDirectedAtMe: true)
        #expect(enriched.section == .directedAtYou)
    }

    @Test("Non-CQ exchange between other stations is allActivity section")
    func otherStationExchangeSection() {
        let decode = makeDecode(
            message: .signalReport(from: "K1ABC", to: "W9XYZ", dB: -11),
            rawText: "W9XYZ K1ABC -11"
        )
        let enriched = makeEnriched(decode: decode)
        #expect(enriched.section == .allActivity)
    }

    // MARK: - Sort Priority Ordering

    @Test("Sort priority ordering: newDXCC < newState < newBand < normal < dupe")
    func sortPriorityOrdering() {
        let newDXCC = makeEnriched(isNewDXCC: true)
        let newState = makeEnriched(isNewState: true)
        let newBand = makeEnriched(isNewBand: true)
        let normal = makeEnriched()
        let dupe = makeEnriched(isDupe: true)

        #expect(newDXCC.sortPriority < newState.sortPriority)
        #expect(newState.sortPriority < newBand.sortPriority)
        #expect(newBand.sortPriority < normal.sortPriority)
        #expect(normal.sortPriority < dupe.sortPriority)
    }

    @Test("newGrid has same priority as newState")
    func newGridPriority() {
        let newState = makeEnriched(isNewState: true)
        let newGrid = makeEnriched(isNewGrid: true)
        #expect(newState.sortPriority == newGrid.sortPriority)
    }

    // MARK: - SNR Tier

    @Test("SNR > -5 is strong tier")
    func snrStrongTier() {
        #expect(FT8EnrichedDecode.snrTier(forSNR: 0) == .strong)
        #expect(FT8EnrichedDecode.snrTier(forSNR: -4) == .strong)
        #expect(FT8EnrichedDecode.snrTier(forSNR: 10) == .strong)
    }

    @Test("SNR -5 to -15 is medium tier")
    func snrMediumTier() {
        #expect(FT8EnrichedDecode.snrTier(forSNR: -5) == .medium)
        #expect(FT8EnrichedDecode.snrTier(forSNR: -12) == .medium)
        #expect(FT8EnrichedDecode.snrTier(forSNR: -15) == .medium)
    }

    @Test("SNR < -15 is weak tier")
    func snrWeakTier() {
        #expect(FT8EnrichedDecode.snrTier(forSNR: -16) == .weak)
        #expect(FT8EnrichedDecode.snrTier(forSNR: -24) == .weak)
    }

    // MARK: - Identity

    @Test("Enriched decode id matches underlying decode id")
    func identityMatchesDecode() {
        let decode = makeDecode()
        let enriched = FT8EnrichedDecode(
            decode: decode,
            dxccEntity: "United States",
            stateProvince: "CT",
            distanceMiles: 150,
            bearing: 45,
            isNewDXCC: false,
            isNewState: false,
            isNewGrid: false,
            isNewBand: false,
            isDupe: false
        )
        #expect(enriched.id == decode.id)
        #expect(enriched.dxccEntity == "United States")
        #expect(enriched.stateProvince == "CT")
        #expect(enriched.distanceMiles == 150)
        #expect(enriched.bearing == 45)
    }

    // MARK: - Section Comparable

    @Test("Section ordering: directedAtYou < callingCQ < allActivity")
    func sectionComparable() {
        #expect(FT8EnrichedDecode.Section.directedAtYou < .callingCQ)
        #expect(FT8EnrichedDecode.Section.callingCQ < .allActivity)
    }

    // MARK: Private

    // MARK: - Test Helpers

    private func makeDecode(
        message: FT8Message = .cq(call: "W1AW", grid: "FN31", modifier: nil),
        snr: Int = -12,
        rawText: String = "CQ W1AW FN31"
    ) -> FT8DecodeResult {
        FT8DecodeResult(
            message: message,
            snr: snr,
            deltaTime: 0.1,
            frequency: 1_500,
            rawText: rawText
        )
    }

    private func makeEnriched(
        decode: FT8DecodeResult? = nil,
        isNewDXCC: Bool = false,
        isNewState: Bool = false,
        isNewGrid: Bool = false,
        isNewBand: Bool = false,
        isDupe: Bool = false,
        isDirectedAtMe: Bool = false
    ) -> FT8EnrichedDecode {
        FT8EnrichedDecode(
            decode: decode ?? makeDecode(),
            dxccEntity: nil,
            stateProvince: nil,
            distanceMiles: nil,
            bearing: nil,
            isNewDXCC: isNewDXCC,
            isNewState: isNewState,
            isNewGrid: isNewGrid,
            isNewBand: isNewBand,
            isDupe: isDupe,
            isDirectedAtMe: isDirectedAtMe
        )
    }
}

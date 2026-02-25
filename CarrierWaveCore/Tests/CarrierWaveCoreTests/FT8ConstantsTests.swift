//
//  FT8ConstantsTests.swift
//  CarrierWaveCoreTests
//

import Testing
@testable import CarrierWaveCore

@Suite("FT8 Constants Tests")
struct FT8ConstantsTests {
    // MARK: - Timing Constants

    @Test("Timing constants have expected values")
    func timingConstants() {
        #expect(FT8Constants.slotDuration == 15.0)
        #expect(FT8Constants.symbolPeriod == 0.160)
        #expect(FT8Constants.toneSpacing == 6.25)
        #expect(FT8Constants.toneCount == 8)
        #expect(FT8Constants.totalSymbols == 79)
        #expect(FT8Constants.sampleRate == 12_000)
    }

    @Test("Derived constants match their component values")
    func derivedConstants() {
        #expect(FT8Constants.txDuration == Double(FT8Constants.totalSymbols) * FT8Constants.symbolPeriod)
        #expect(FT8Constants.samplesPerSlot == FT8Constants.sampleRate * Int(FT8Constants.slotDuration))
    }

    // MARK: - Dial Frequencies

    @Test("dialFrequency returns correct frequency for 20m")
    func dialFrequency20m() {
        #expect(FT8Constants.dialFrequency(forBand: "20m") == 14.074)
    }

    @Test("dialFrequency returns correct frequency for 40m")
    func dialFrequency40m() {
        #expect(FT8Constants.dialFrequency(forBand: "40m") == 7.074)
    }

    @Test("dialFrequency returns correct frequency for 80m")
    func dialFrequency80m() {
        #expect(FT8Constants.dialFrequency(forBand: "80m") == 3.573)
    }

    @Test("dialFrequency returns correct frequency for 10m")
    func dialFrequency10m() {
        #expect(FT8Constants.dialFrequency(forBand: "10m") == 28.074)
    }

    @Test("dialFrequency returns correct frequency for 6m")
    func dialFrequency6m() {
        #expect(FT8Constants.dialFrequency(forBand: "6m") == 50.313)
    }

    @Test("dialFrequency returns correct frequency for 160m")
    func dialFrequency160m() {
        #expect(FT8Constants.dialFrequency(forBand: "160m") == 1.840)
    }

    @Test("dialFrequency returns nil for unknown band")
    func dialFrequencyUnknown() {
        #expect(FT8Constants.dialFrequency(forBand: "4m") == nil)
        #expect(FT8Constants.dialFrequency(forBand: "") == nil)
    }

    @Test("band returns correct band for 14.074 MHz")
    func bandFor14074() {
        #expect(FT8Constants.band(forDialFrequency: 14.074) == "20m")
    }

    @Test("band returns correct band for 7.074 MHz")
    func bandFor7074() {
        #expect(FT8Constants.band(forDialFrequency: 7.074) == "40m")
    }

    @Test("band returns nil for unknown frequency")
    func bandForUnknown() {
        #expect(FT8Constants.band(forDialFrequency: 99.999) == nil)
    }

    @Test("supportedBands are in frequency order")
    func supportedBandsOrder() throws {
        let bands = FT8Constants.supportedBands
        #expect(bands.count == 13)
        #expect(bands.first == "160m")
        #expect(bands.last == "70cm")
        // Verify 20m comes after 30m
        let idx20 = try #require(bands.firstIndex(of: "20m"))
        let idx30 = try #require(bands.firstIndex(of: "30m"))
        #expect(idx20 > idx30)
    }
}

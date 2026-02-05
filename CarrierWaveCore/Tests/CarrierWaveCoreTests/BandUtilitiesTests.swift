//
//  BandUtilitiesTests.swift
//  CarrierWaveCoreTests
//

import Testing
@testable import CarrierWaveCore

@Suite("Band Utilities Tests")
struct BandUtilitiesTests {
    @Test("Derive band from frequency - all bands")
    func deriveBandFromFrequency() {
        // Test each amateur band
        #expect(BandUtilities.deriveBand(from: 1_900) == "160m")
        #expect(BandUtilities.deriveBand(from: 3_500) == "80m")
        #expect(BandUtilities.deriveBand(from: 5_350) == "60m")
        #expect(BandUtilities.deriveBand(from: 7_150) == "40m")
        #expect(BandUtilities.deriveBand(from: 10_125) == "30m")
        #expect(BandUtilities.deriveBand(from: 14_060) == "20m")
        #expect(BandUtilities.deriveBand(from: 18_100) == "17m")
        #expect(BandUtilities.deriveBand(from: 21_200) == "15m")
        #expect(BandUtilities.deriveBand(from: 24_930) == "12m")
        #expect(BandUtilities.deriveBand(from: 28_500) == "10m")
        #expect(BandUtilities.deriveBand(from: 50_125) == "6m")
        #expect(BandUtilities.deriveBand(from: 146_520) == "2m")
        #expect(BandUtilities.deriveBand(from: 432_100) == "70cm")
    }

    @Test("Derive band from nil frequency")
    func deriveBandFromNilFrequency() {
        #expect(BandUtilities.deriveBand(from: nil) == nil)
    }

    @Test("Derive band from out-of-band frequency")
    func deriveBandFromOutOfBandFrequency() {
        #expect(BandUtilities.deriveBand(from: 1_000) == nil) // Below 160m
        #expect(BandUtilities.deriveBand(from: 100_000) == nil) // Between 6m and 2m
        #expect(BandUtilities.deriveBand(from: 900_000) == nil) // Above 70cm
    }

    @Test("Band order is correct")
    func bandOrderIsCorrect() {
        let expected = [
            "160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m", "6m", "2m",
            "70cm", "Other",
        ]
        #expect(BandUtilities.bandOrder == expected)
    }
}

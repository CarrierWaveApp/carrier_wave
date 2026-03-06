import Foundation
import Testing
@testable import CWSweep

@Test func bandLookupFromFrequency() {
    let band20m = BandEdges.band(for: 14_074.0)
    #expect(band20m?.id == "20m")
    #expect(band20m?.lowerKHz == 14_000)
    #expect(band20m?.upperKHz == 14_350)

    let band40m = BandEdges.band(for: 7_030.0)
    #expect(band40m?.id == "40m")

    let band80m = BandEdges.band(for: 3_573.0)
    #expect(band80m?.id == "80m")

    let band10m = BandEdges.band(for: 28_074.0)
    #expect(band10m?.id == "10m")

    let band6m = BandEdges.band(for: 50_313.0)
    #expect(band6m?.id == "6m")
}

@Test func bandLookupOutOfRange() {
    let noband = BandEdges.band(for: 100_000.0)
    #expect(noband == nil)

    let belowHF = BandEdges.band(for: 100.0)
    #expect(belowHF == nil)
}

@Test func xPositionCalculation() throws {
    let band = try #require(BandEdges.hfBands.first { $0.id == "20m" })

    // At lower edge -> 0.0
    let xLower = BandEdges.xPosition(frequencyKHz: 14_000, in: band)
    #expect(abs(xLower) < 0.001)

    // At upper edge -> 1.0
    let xUpper = BandEdges.xPosition(frequencyKHz: 14_350, in: band)
    #expect(abs(xUpper - 1.0) < 0.001)

    // At midpoint -> ~0.5
    let xMid = BandEdges.xPosition(frequencyKHz: 14_175, in: band)
    #expect(abs(xMid - 0.5) < 0.01)
}

@Test func frequencyFromXPosition() throws {
    let band = try #require(BandEdges.hfBands.first { $0.id == "20m" })

    let freqLower = BandEdges.frequency(xPosition: 0.0, in: band)
    #expect(abs(freqLower - 14_000) < 0.01)

    let freqUpper = BandEdges.frequency(xPosition: 1.0, in: band)
    #expect(abs(freqUpper - 14_350) < 0.01)

    let freqMid = BandEdges.frequency(xPosition: 0.5, in: band)
    #expect(abs(freqMid - 14_175) < 0.01)
}

@Test func xPositionRoundtrip() throws {
    let band = try #require(BandEdges.hfBands.first { $0.id == "40m" })
    let freq = 7_074.0

    let x = BandEdges.xPosition(frequencyKHz: freq, in: band)
    let roundtrip = BandEdges.frequency(xPosition: x, in: band)
    #expect(abs(roundtrip - freq) < 0.01)
}

@Test func bandEdgesWidthKHz() throws {
    let band20m = try #require(BandEdges.hfBands.first { $0.id == "20m" })
    #expect(band20m.widthKHz == 350)

    let band30m = try #require(BandEdges.hfBands.first { $0.id == "30m" })
    #expect(band30m.widthKHz == 50)
}

@Test func allBandsHavePositiveWidth() {
    for band in BandEdges.hfBands {
        #expect(band.widthKHz > 0, "Band \(band.id) should have positive width")
        #expect(band.upperKHz > band.lowerKHz, "Band \(band.id) upper > lower")
    }
}

@Test func digitalBoundariesWithinBand() {
    for band in BandEdges.hfBands {
        if let db = band.digitalBoundaryKHz {
            #expect(db >= band.lowerKHz, "Digital boundary for \(band.id) should be >= lower edge")
            #expect(db <= band.upperKHz, "Digital boundary for \(band.id) should be <= upper edge")
        }
    }
}

@Test func ssbBoundariesWithinBand() {
    for band in BandEdges.hfBands {
        if let sb = band.ssbBoundaryKHz {
            #expect(sb >= band.lowerKHz, "SSB boundary for \(band.id) should be >= lower edge")
            #expect(sb <= band.upperKHz, "SSB boundary for \(band.id) should be <= upper edge")
        }
    }
}

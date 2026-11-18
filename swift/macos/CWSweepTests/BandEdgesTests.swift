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
    let band = try #require(BandEdges.bands.first { $0.id == "20m" })

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
    let band = try #require(BandEdges.bands.first { $0.id == "20m" })

    let freqLower = BandEdges.frequency(xPosition: 0.0, in: band)
    #expect(abs(freqLower - 14_000) < 0.01)

    let freqUpper = BandEdges.frequency(xPosition: 1.0, in: band)
    #expect(abs(freqUpper - 14_350) < 0.01)

    let freqMid = BandEdges.frequency(xPosition: 0.5, in: band)
    #expect(abs(freqMid - 14_175) < 0.01)
}

@Test func xPositionRoundtrip() throws {
    let band = try #require(BandEdges.bands.first { $0.id == "40m" })
    let freq = 7_074.0

    let x = BandEdges.xPosition(frequencyKHz: freq, in: band)
    let roundtrip = BandEdges.frequency(xPosition: x, in: band)
    #expect(abs(roundtrip - freq) < 0.01)
}

@Test func bandEdgesWidthKHz() throws {
    let band20m = try #require(BandEdges.bands.first { $0.id == "20m" })
    #expect(band20m.widthKHz == 350)

    let band30m = try #require(BandEdges.bands.first { $0.id == "30m" })
    #expect(band30m.widthKHz == 50)
}

@Test func allBandsHavePositiveWidth() {
    for band in BandEdges.bands {
        #expect(band.widthKHz > 0, "Band \(band.id) should have positive width")
        #expect(band.upperKHz > band.lowerKHz, "Band \(band.id) upper > lower")
    }
}

@Test func digitalBoundariesWithinBand() {
    for band in BandEdges.bands {
        if let db = band.digitalBoundaryKHz {
            #expect(db >= band.lowerKHz, "Digital boundary for \(band.id) should be >= lower edge")
            #expect(db <= band.upperKHz, "Digital boundary for \(band.id) should be <= upper edge")
        }
    }
}

@Test func ssbBoundariesWithinBand() {
    for band in BandEdges.bands {
        if let sb = band.ssbBoundaryKHz {
            #expect(sb >= band.lowerKHz, "SSB boundary for \(band.id) should be >= lower edge")
            #expect(sb <= band.upperKHz, "SSB boundary for \(band.id) should be <= upper edge")
        }
    }
}

// MARK: - VHF/UHF

@Test func vhfUHFBandsAreFound() throws {
    #expect(BandEdges.band(for: 146_520)?.id == "2m")
    #expect(BandEdges.band(for: 223_500)?.id == "1.25m")
    #expect(BandEdges.band(for: 446_000)?.id == "70cm")
    #expect(BandEdges.band(for: 927_500)?.id == "33cm")
    #expect(BandEdges.band(for: 1_296_100)?.id == "23cm")
    let ids = BandEdges.bands.map(\.id)
    #expect(try #require(ids.firstIndex(of: "6m")) < #require(ids.firstIndex(of: "2m")))
}

@Test func modeSegmentsSitInsideTheirBand() {
    for band in BandEdges.bands {
        for segment in band.modeSegments {
            #expect(segment.lowerKHz >= band.lowerKHz && segment.upperKHz <= band.upperKHz, "\(band.id)")
            #expect(segment.upperKHz > segment.lowerKHz, "\(band.id)")
        }
    }
}

@Test func vhfSegmentModes() throws {
    let twoM = try #require(BandEdges.band(for: 144_000))
    #expect(twoM.segmentMode(frequencyKHz: 144_050) == "CW")
    #expect(twoM.segmentMode(frequencyKHz: 144_200) == "SSB")
    #expect(twoM.segmentMode(frequencyKHz: 146_520) == "FM")
    // 70cm below the weak-signal segment is not CW (the HF model's flaw).
    let seventy = try #require(BandEdges.band(for: 425_000))
    #expect(seventy.segmentMode(frequencyKHz: 425_000) == nil)
    #expect(seventy.digitalBoundaryKHz == nil)
}

@Test func wideBandsZoomDeeper() throws {
    #expect(try #require(BandEdges.band(for: 14_000)).maxZoomScale == 16)
    #expect(try #require(BandEdges.band(for: 1_296_000)).maxZoomScale == 240)
}

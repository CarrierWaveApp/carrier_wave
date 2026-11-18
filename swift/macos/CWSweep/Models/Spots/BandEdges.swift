import Foundation

// MARK: - BandEdge

/// Band edge frequency definitions for band map canvas rendering
struct BandEdge: Identifiable {
    // MARK: Internal

    let id: String
    let label: String
    let lowerKHz: Double
    let upperKHz: Double

    /// CW/digital boundary (approximate)
    var digitalBoundaryKHz: Double? {
        switch id {
        case "160m": 1_840
        case "80m": 3_570
        case "60m": nil
        case "40m": 7_070
        case "30m": 10_130
        case "20m": 14_070
        case "17m": 18_095
        case "15m": 21_070
        case "12m": 24_910
        case "10m": 28_070
        case "6m": 50_300
        default: nil
        }
    }

    /// SSB boundary (approximate)
    var ssbBoundaryKHz: Double? {
        switch id {
        case "160m": 1_840
        case "80m": 3_600
        case "60m": nil
        case "40m": 7_125
        case "30m": nil // CW/digital only
        case "20m": 14_150
        case "17m": 18_110
        case "15m": 21_200
        case "12m": 24_930
        case "10m": 28_300
        case "6m": 50_100
        default: nil
        }
    }

    /// Width in kHz
    var widthKHz: Double {
        upperKHz - lowerKHz
    }

    /// Deepest band-map zoom: 16× on HF, more on wide VHF/UHF bands so any
    /// band can zoom to ~250 kHz across (23cm: 240×).
    var maxZoomScale: CGFloat {
        max(16, widthKHz / 250)
    }

    /// VHF/UHF mode segments (ARRL band plan, simplified). HF bands use the
    /// two boundaries above instead; on VHF those would call everything below
    /// the weak-signal segment (e.g. 420–432 MHz) CW.
    var modeSegments: [BandModeSegment] {
        switch id {
        case "2m": [.cw(144_000, 144_100), .ssb(144_100, 144_300), .fm(144_500, 148_000)]
        case "1.25m": [.cw(222_000, 222_050), .ssb(222_050, 222_150), .fm(222_150, 225_000)]
        case "70cm": [.cw(432_000, 432_100), .ssb(432_100, 432_300), .fm(440_000, 450_000)]
        case "33cm": Self.segments33cm
        case "23cm": Self.segments23cm
        default: []
        }
    }

    /// Mode for a frequency from `modeSegments`, nil outside them or on HF.
    func segmentMode(frequencyKHz: Double) -> String? {
        modeSegments.first { frequencyKHz >= $0.lowerKHz && frequencyKHz < $0.upperKHz }?.mode
    }

    // MARK: Private

    private static let segments33cm: [BandModeSegment] = [
        .cw(902_000, 902_100), .ssb(902_100, 902_300),
        .cw(903_000, 903_100), .ssb(903_100, 903_400), .fm(927_000, 928_000),
    ]

    private static let segments23cm: [BandModeSegment] = [
        .fm(1_282_000, 1_288_000), .fm(1_294_000, 1_295_000),
        .cw(1_296_000, 1_296_050), .ssb(1_296_050, 1_296_250),
    ]
}

// MARK: - BandModeSegment

struct BandModeSegment {
    let lowerKHz: Double
    let upperKHz: Double
    let mode: String

    static func cw(_ lower: Double, _ upper: Double) -> BandModeSegment {
        BandModeSegment(lowerKHz: lower, upperKHz: upper, mode: "CW")
    }

    static func ssb(_ lower: Double, _ upper: Double) -> BandModeSegment {
        BandModeSegment(lowerKHz: lower, upperKHz: upper, mode: "SSB")
    }

    static func fm(_ lower: Double, _ upper: Double) -> BandModeSegment {
        BandModeSegment(lowerKHz: lower, upperKHz: upper, mode: "FM")
    }
}

// MARK: - BandEdges

enum BandEdges {
    /// 160m through 23cm, low to high.
    static let bands: [BandEdge] = [
        BandEdge(id: "160m", label: "160m", lowerKHz: 1_800, upperKHz: 2_000),
        BandEdge(id: "80m", label: "80m", lowerKHz: 3_500, upperKHz: 4_000),
        BandEdge(id: "60m", label: "60m", lowerKHz: 5_330, upperKHz: 5_405),
        BandEdge(id: "40m", label: "40m", lowerKHz: 7_000, upperKHz: 7_300),
        BandEdge(id: "30m", label: "30m", lowerKHz: 10_100, upperKHz: 10_150),
        BandEdge(id: "20m", label: "20m", lowerKHz: 14_000, upperKHz: 14_350),
        BandEdge(id: "17m", label: "17m", lowerKHz: 18_068, upperKHz: 18_168),
        BandEdge(id: "15m", label: "15m", lowerKHz: 21_000, upperKHz: 21_450),
        BandEdge(id: "12m", label: "12m", lowerKHz: 24_890, upperKHz: 24_990),
        BandEdge(id: "10m", label: "10m", lowerKHz: 28_000, upperKHz: 29_700),
        BandEdge(id: "6m", label: "6m", lowerKHz: 50_000, upperKHz: 54_000),
        BandEdge(id: "2m", label: "2m", lowerKHz: 144_000, upperKHz: 148_000),
        BandEdge(id: "1.25m", label: "1.25m", lowerKHz: 222_000, upperKHz: 225_000),
        BandEdge(id: "70cm", label: "70cm", lowerKHz: 420_000, upperKHz: 450_000),
        BandEdge(id: "33cm", label: "33cm", lowerKHz: 902_000, upperKHz: 928_000),
        BandEdge(id: "23cm", label: "23cm", lowerKHz: 1_240_000, upperKHz: 1_300_000),
    ]

    /// Find the band edge for a given frequency in kHz
    static func band(for frequencyKHz: Double) -> BandEdge? {
        bands.first { frequencyKHz >= $0.lowerKHz && frequencyKHz <= $0.upperKHz }
    }

    /// Convert a frequency to an x-position within a band (0.0 to 1.0)
    static func xPosition(frequencyKHz: Double, in bandEdge: BandEdge) -> Double {
        let clamped = min(max(frequencyKHz, bandEdge.lowerKHz), bandEdge.upperKHz)
        return (clamped - bandEdge.lowerKHz) / bandEdge.widthKHz
    }

    /// Convert an x-position (0.0 to 1.0) to a frequency within a band
    static func frequency(xPosition: Double, in bandEdge: BandEdge) -> Double {
        bandEdge.lowerKHz + xPosition * bandEdge.widthKHz
    }
}

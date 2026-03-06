import Foundation

// MARK: - BandEdge

/// Band edge frequency definitions for band map canvas rendering
struct BandEdge: Identifiable, Sendable {
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
}

// MARK: - BandEdges

enum BandEdges {
    static let hfBands: [BandEdge] = [
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
    ]

    /// Find the band edge for a given frequency in kHz
    static func band(for frequencyKHz: Double) -> BandEdge? {
        hfBands.first { frequencyKHz >= $0.lowerKHz && frequencyKHz <= $0.upperKHz }
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

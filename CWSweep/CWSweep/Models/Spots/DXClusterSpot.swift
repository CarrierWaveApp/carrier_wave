import CarrierWaveCore
import Foundation

/// A parsed DX cluster spot
struct DXClusterSpot: Identifiable, Sendable {
    // MARK: Internal

    let id = UUID()
    let spotter: String
    let frequencyKHz: Double
    let callsign: String
    let comment: String
    let timestamp: Date

    /// Frequency in MHz
    var frequencyMHz: Double {
        frequencyKHz / 1_000.0
    }

    /// Band derived from frequency
    var band: String {
        BandUtilities.deriveBand(from: frequencyKHz) ?? ""
    }

    /// Mode parsed from comment text, falling back to frequency-based guess
    var parsedMode: String {
        DXSpotParser.parseMode(from: comment) ?? guessMode()
    }

    /// CW speed parsed from comment (e.g. "28 WPM")
    var cwSpeed: Int? {
        DXSpotParser.parseCWSpeed(from: comment)
    }

    /// Deduplication key: callsign + band
    var dedupKey: String {
        "\(callsign.uppercased())-\(band)"
    }

    /// Convert to a UnifiedSpot
    func toUnifiedSpot() -> UnifiedSpot {
        UnifiedSpot(
            id: "cluster-\(id.uuidString)",
            callsign: callsign,
            frequencyKHz: frequencyKHz,
            mode: parsedMode,
            timestamp: timestamp,
            source: .cluster,
            snr: nil,
            wpm: cwSpeed,
            spotter: spotter,
            spotterGrid: nil,
            parkRef: nil,
            parkName: nil,
            comments: comment.isEmpty ? nil : comment,
            locationDesc: nil
        )
    }

    // MARK: Private

    /// Guess mode from frequency position within band
    private func guessMode() -> String {
        if let edge = BandEdges.band(for: frequencyKHz) {
            if let digitalBound = edge.digitalBoundaryKHz, frequencyKHz < digitalBound {
                return "CW"
            }
            if let ssbBound = edge.ssbBoundaryKHz, frequencyKHz >= ssbBound {
                return "SSB"
            }
            return "DIGI"
        }
        return "CW"
    }
}

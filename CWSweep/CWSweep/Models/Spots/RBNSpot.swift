import CarrierWaveCore
import Foundation

// MARK: - RBNSpot

/// A spot from the Reverse Beacon Network
struct RBNSpot: Decodable, Identifiable, Sendable {
    enum CodingKeys: String, CodingKey {
        case id
        case callsign
        case frequency
        case mode
        case timestamp
        case snr
        case wpm
        case spotter
        case spotterGrid = "spotter_grid"
    }

    let id: Int
    let callsign: String
    let frequency: Double // in kHz
    let mode: String
    let timestamp: Date
    let snr: Int
    let wpm: Int?
    let spotter: String
    let spotterGrid: String?

    /// Frequency in MHz
    var frequencyMHz: Double {
        frequency / 1_000.0
    }

    /// Band derived from frequency
    var band: String {
        BandUtilities.deriveBand(from: frequency) ?? ""
    }

    /// Formatted frequency string
    var formattedFrequency: String {
        String(format: "%.1f kHz", frequency)
    }

    /// Time ago string
    var timeAgo: String {
        let seconds = Date().timeIntervalSince(timestamp)
        if seconds < 60 {
            return "\(Int(seconds))s ago"
        } else if seconds < 3_600 {
            return "\(Int(seconds / 60))m ago"
        } else {
            return "\(Int(seconds / 3_600))h ago"
        }
    }
}

// MARK: - RBNSpotsResponse

/// Response from the /spots endpoint (with total count)
struct RBNSpotsResponse: Decodable, Sendable {
    let total: Int
    let spots: [RBNSpot]
}

// MARK: - RBNCallsignSpotsResponse

/// Response from the /spots/callsign endpoint (array only)
struct RBNCallsignSpotsResponse: Decodable, Sendable {
    let spots: [RBNSpot]
}

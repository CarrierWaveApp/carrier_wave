import CarrierWaveCore
import CarrierWaveData
import Foundation

// MARK: - UnifiedSpot

/// A spot from any source in a unified format
struct UnifiedSpot: Identifiable, Sendable, Equatable {
    // MARK: Internal

    let id: String
    let callsign: String
    let frequencyKHz: Double
    let mode: String
    let timestamp: Date
    let source: SpotSource

    // RBN-specific fields
    let snr: Int?
    let wpm: Int?
    let spotter: String?
    var spotterGrid: String?

    // POTA-specific fields
    let parkRef: String?
    let parkName: String?
    let comments: String?

    // SOTA-specific fields
    var summitCode: String?
    var summitName: String?
    var summitPoints: Int?

    // WWFF-specific fields
    var wwffRef: String?
    var wwffName: String?

    // Location fields
    let locationDesc: String?
    var stateAbbr: String?

    /// Frequency in MHz
    var frequencyMHz: Double {
        frequencyKHz / 1_000.0
    }

    /// Band derived from frequency
    var band: String {
        BandUtilities.deriveBand(from: frequencyKHz) ?? ""
    }

    /// Formatted frequency string
    var formattedFrequency: String {
        String(format: "%.1f kHz", frequencyKHz)
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

    /// Deduplication key: callsign + band
    var dedupKey: String {
        "\(callsign.uppercased())-\(band)"
    }

    /// Display name for the reference (park, summit, or WWFF ref)
    var referenceDisplay: String? {
        parkRef ?? summitCode ?? wwffRef
    }

    /// Display name for the location
    var locationDisplay: String? {
        parkName ?? summitName ?? wwffName
    }

    /// Check if this spot is a self-spot for the given user callsign
    func isSelfSpot(userCallsign: String) -> Bool {
        let normalizedUser = Self.normalizeCallsign(userCallsign)
        let normalizedSpot = Self.normalizeCallsign(callsign)
        return normalizedUser == normalizedSpot
    }

    // MARK: Private

    private static func normalizeCallsign(_ callsign: String) -> String {
        let upper = callsign.uppercased()
        if let slashIndex = upper.firstIndex(of: "/") {
            return String(upper[..<slashIndex])
        }
        return upper
    }
}

// MARK: - Factory methods

extension UnifiedSpot {
    /// Create from an RBN spot
    static func from(rbn spot: RBNSpot) -> UnifiedSpot {
        UnifiedSpot(
            id: "rbn-\(spot.id)",
            callsign: spot.callsign,
            frequencyKHz: spot.frequency,
            mode: spot.mode,
            timestamp: spot.timestamp,
            source: .rbn,
            snr: spot.snr,
            wpm: spot.wpm,
            spotter: spot.spotter,
            spotterGrid: spot.spotterGrid,
            parkRef: nil,
            parkName: nil,
            comments: nil,
            locationDesc: nil
        )
    }

    /// Create from a POTA spot
    static func from(pota spot: POTASpot) -> UnifiedSpot? {
        guard let freqKHz = spot.frequencyKHz,
              let timestamp = spot.timestamp
        else {
            return nil
        }

        return UnifiedSpot(
            id: "pota-\(spot.spotId)",
            callsign: spot.activator,
            frequencyKHz: freqKHz,
            mode: spot.mode,
            timestamp: timestamp,
            source: .pota,
            snr: nil,
            wpm: nil,
            spotter: spot.spotter,
            spotterGrid: nil,
            parkRef: spot.reference,
            parkName: spot.parkName,
            comments: spot.comments,
            locationDesc: spot.locationDesc,
            stateAbbr: POTASpot.parseState(from: spot.locationDesc)
        )
    }

    /// Create from a SOTA spot
    static func from(sota spot: SOTASpot) -> UnifiedSpot? {
        guard let freqKHz = spot.frequencyKHz,
              let timestamp = spot.parsedTimestamp
        else {
            return nil
        }

        return UnifiedSpot(
            id: "sota-\(spot.id)",
            callsign: spot.activatorCallsign,
            frequencyKHz: freqKHz,
            mode: spot.mode,
            timestamp: timestamp,
            source: .sota,
            snr: nil,
            wpm: nil,
            spotter: spot.spotterCallsign,
            spotterGrid: nil,
            parkRef: nil,
            parkName: nil,
            comments: spot.comments,
            summitCode: spot.fullSummitReference,
            summitName: spot.summitName,
            summitPoints: spot.points,
            locationDesc: nil
        )
    }

    /// Create from a WWFF spot
    static func from(wwff spot: WWFFSpot) -> UnifiedSpot? {
        guard let freqKHz = spot.frequencyKHz,
              let timestamp = spot.parsedTimestamp
        else {
            return nil
        }

        return UnifiedSpot(
            id: "wwff-\(spot.id)",
            callsign: spot.activator,
            frequencyKHz: freqKHz,
            mode: spot.mode,
            timestamp: timestamp,
            source: .wwff,
            snr: nil,
            wpm: nil,
            spotter: spot.spotter,
            spotterGrid: nil,
            parkRef: nil,
            parkName: nil,
            comments: spot.comments,
            wwffRef: spot.reference,
            wwffName: spot.locationName,
            locationDesc: nil
        )
    }
}

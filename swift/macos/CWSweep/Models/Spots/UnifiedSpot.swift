import CarrierWaveCore
import CarrierWaveData
import Foundation

// MARK: - UnifiedSpot

/// A spot from any source in a unified format
struct UnifiedSpot: Identifiable, Equatable {
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

    // DX web spot enrichment fields
    var dxGrid: String?
    var continent: String?
    var splitInfo: String?
    var lotwUser: Bool?
    var dxccPrefix: String?
    var cqZone: Int?
    var iotaRef: String?

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

    /// Create from a DX Summit spot
    static func from(dxSummit spot: DXSummitSpot) -> UnifiedSpot {
        let mode = guessMode(comment: spot.info, frequencyKHz: spot.frequency)
        let splitInfo = SplitInfoParser.parse(spot.info)
        return UnifiedSpot(
            id: "dxs-\(spot.id)",
            callsign: spot.dxCall,
            frequencyKHz: spot.frequency,
            mode: mode,
            timestamp: spot.time,
            source: .dxSummit,
            snr: nil,
            wpm: nil,
            spotter: spot.deCall,
            spotterGrid: nil,
            parkRef: nil,
            parkName: nil,
            comments: spot.info,
            splitInfo: splitInfo,
            locationDesc: spot.dxCountry
        )
    }

    /// Create from a DXHeat spot
    static func from(dxHeat spot: DXHeatSpot) -> UnifiedSpot? {
        guard let freqKHz = Double(spot.frequency) else {
            return nil
        }
        let timestamp = DXHeatSpot.parseTimestamp(date: spot.date, time: spot.time)
        let comment = DXHeatSpot.decodeHTMLEntities(spot.comment ?? "")
        let splitInfo = SplitInfoParser.parse(comment)
        let mode = spot.mode ?? guessMode(comment: comment, frequencyKHz: freqKHz)
        return UnifiedSpot(
            id: "dxh-\(spot.nr)",
            callsign: spot.dxCall,
            frequencyKHz: freqKHz,
            mode: mode,
            timestamp: timestamp ?? Date(),
            source: .dxHeat,
            snr: nil,
            wpm: nil,
            spotter: spot.spotter,
            spotterGrid: nil,
            parkRef: nil,
            parkName: nil,
            comments: comment.isEmpty ? nil : comment,
            dxGrid: spot.dxLocator,
            continent: spot.continentDX,
            splitInfo: splitInfo,
            lotwUser: spot.lotw,
            locationDesc: nil
        )
    }

    /// Create from a DXWatch spot with optional call info
    static func from(dxWatch spot: DXWatchSpot, callInfo: DXWatchCallInfo?) -> UnifiedSpot {
        let mode = guessMode(comment: spot.comment, frequencyKHz: spot.frequency)
        let splitInfo = SplitInfoParser.parse(spot.comment)
        return UnifiedSpot(
            id: "dxw-\(spot.id)",
            callsign: spot.dxCall,
            frequencyKHz: spot.frequency,
            mode: mode,
            timestamp: spot.timestamp ?? Date(),
            source: .dxWatch,
            snr: nil,
            wpm: nil,
            spotter: spot.spotter,
            spotterGrid: nil,
            parkRef: nil,
            parkName: nil,
            comments: spot.comment,
            dxGrid: callInfo?.grid,
            continent: callInfo?.continent,
            splitInfo: splitInfo,
            dxccPrefix: callInfo?.prefix,
            cqZone: callInfo?.cqZone,
            iotaRef: callInfo?.iotaRef,
            locationDesc: callInfo?.entityName
        )
    }

    /// Guess mode from comment text and frequency position within band
    private static func guessMode(comment: String?, frequencyKHz: Double) -> String {
        // Try parsing mode from comment first (e.g. "FT8", "CW", "SSB")
        if let comment, let parsed = DXSpotParser.parseMode(from: comment) {
            return parsed
        }
        // Fall back to frequency-based heuristic using band edges
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

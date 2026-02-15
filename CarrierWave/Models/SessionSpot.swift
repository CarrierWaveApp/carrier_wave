import Foundation
import SwiftData

// MARK: - SessionSpot

/// A persisted spot (RBN or POTA) recorded during a logging session.
/// Linked to LoggingSession via `loggingSessionId` (same pattern as QSO).
@Model
final class SessionSpot {
    // MARK: Lifecycle

    init(
        loggingSessionId: UUID,
        callsign: String,
        frequencyKHz: Double,
        mode: String,
        timestamp: Date,
        source: String,
        snr: Int? = nil,
        wpm: Int? = nil,
        spotter: String? = nil,
        spotterGrid: String? = nil,
        parkRef: String? = nil,
        parkName: String? = nil,
        comments: String? = nil,
        region: String = SpotRegion.other.rawValue,
        distanceMeters: Double? = nil
    ) {
        id = UUID()
        self.loggingSessionId = loggingSessionId
        self.callsign = callsign
        self.frequencyKHz = frequencyKHz
        self.mode = mode
        self.timestamp = timestamp
        self.source = source
        self.snr = snr
        self.wpm = wpm
        self.spotter = spotter
        self.spotterGrid = spotterGrid
        self.parkRef = parkRef
        self.parkName = parkName
        self.comments = comments
        self.region = region
        self.distanceMeters = distanceMeters
    }

    // MARK: Internal

    var id: UUID
    var loggingSessionId: UUID

    // Core fields
    var callsign: String
    var frequencyKHz: Double
    var mode: String
    var timestamp: Date
    /// "rbn" or "pota"
    var source: String

    // RBN-specific
    var snr: Int?
    var wpm: Int?
    var spotter: String?
    var spotterGrid: String?

    // POTA-specific
    var parkRef: String?
    var parkName: String?
    var comments: String?

    // Enrichment
    var region: String
    var distanceMeters: Double?

    /// Dedup key to prevent re-inserting the same spot across polling cycles
    var dedupKey: String {
        "\(source)-\(callsign)-\(Int(frequencyKHz))-\(Int(timestamp.timeIntervalSince1970))"
    }

    /// Whether this is a POTA spot
    var isPOTA: Bool {
        source == "pota"
    }

    /// Whether this is an RBN spot
    var isRBN: Bool {
        source == "rbn"
    }

    /// SpotRegion enum accessor
    var spotRegion: SpotRegion {
        SpotRegion(rawValue: region) ?? .other
    }

    /// Frequency in MHz
    var frequencyMHz: Double {
        frequencyKHz / 1_000.0
    }

    /// Create from an EnrichedSpot
    static func from(
        _ enriched: EnrichedSpot,
        loggingSessionId: UUID
    ) -> SessionSpot {
        let spot = enriched.spot
        // Derive source from spot id prefix (e.g. "rbn-123" or "pota-456")
        let sourceString = spot.id.hasPrefix("pota") ? "pota" : "rbn"
        return SessionSpot(
            loggingSessionId: loggingSessionId,
            callsign: spot.callsign,
            frequencyKHz: spot.frequencyKHz,
            mode: spot.mode,
            timestamp: spot.timestamp,
            source: sourceString,
            snr: spot.snr,
            wpm: spot.wpm,
            spotter: spot.spotter,
            spotterGrid: spot.spotterGrid,
            parkRef: spot.parkRef,
            parkName: spot.parkName,
            comments: spot.comments,
            region: enriched.region.rawValue,
            distanceMeters: enriched.distanceMeters
        )
    }
}

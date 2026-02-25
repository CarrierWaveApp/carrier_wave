import Foundation
import SwiftData

// MARK: - SessionSpot

/// A persisted spot (RBN or POTA) recorded during a logging session.
/// Linked to LoggingSession via `loggingSessionId` (same pattern as QSO).
@Model
nonisolated final class SessionSpot {
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

    var id = UUID()
    var loggingSessionId = UUID()

    // Core fields
    var callsign = ""
    var frequencyKHz: Double = 0
    var mode = ""
    var timestamp = Date()
    /// "rbn" or "pota"
    var source = ""

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
    var region = SpotRegion.other.rawValue
    var distanceMeters: Double?

    /// Cloud sync
    var cloudDirtyFlag = false

    /// Dedup key to prevent re-inserting the same spot across polling cycles
    var dedupKey: String {
        "\(source)-\(callsign)-\(Int(frequencyKHz))-\(Int(timestamp.timeIntervalSince1970))"
    }

    /// Whether this is a human/POTA spot (excludes RBN relays via POTA API)
    var isPOTA: Bool {
        source == "pota" && !isRBNRelay
    }

    /// Whether the activator spotted themselves (announcement, not an incoming spot)
    var isSelfSpot: Bool {
        isPOTA && spotter?.uppercased() == callsign.uppercased()
    }

    /// Whether this is an RBN spot (includes RBN relays via POTA API)
    var isRBN: Bool {
        source == "rbn" || isRBNRelay
    }

    /// RBN spots relayed through POTA API have source "pota" but
    /// comments starting with "RBN" (e.g. "RBN 10 dB 25 WPM via VE7CC-#")
    var isRBNRelay: Bool {
        source == "pota" && (comments?.hasPrefix("RBN") ?? false)
    }

    /// SpotRegion enum accessor
    var spotRegion: SpotRegion {
        SpotRegion(rawValue: region) ?? .other
    }

    /// Derived amateur band from frequency (e.g. "20m")
    var band: String? {
        BandUtilities.deriveBand(from: frequencyKHz)
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

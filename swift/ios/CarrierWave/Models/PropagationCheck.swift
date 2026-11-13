import CarrierWaveData
import Foundation
import SwiftData

// MARK: - PropagationCheck

/// A saved record of a "How's my antenna?" propagation check session.
///
/// Mirrors the `ActivityItem` opaque-blob precedent: headline statistics
/// are denormalized into columns for fast list rendering; raw spots are
/// stored as compressed JSON in `spotsBlob` and decoded lazily on the
/// detail view.
@Model
nonisolated final class PropagationCheck {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        label: String,
        startedAt: Date,
        endedAt: Date,
        callsignUsed: String,
        userGridUsed: String,
        bandsRequested: [String],
        transmitMode: String,
        stopReason: String,
        totalSpots: Int = 0,
        uniqueSkimmers: Int = 0,
        bandsWithActivity: [String] = [],
        maxDistanceKm: Double = 0,
        peakSNRdB: Double = 0,
        notes: String? = nil,
        radio: String? = nil,
        antenna: String? = nil,
        key: String? = nil,
        mic: String? = nil,
        spotsBlob: Data = Data(),
        spotsBlobSchemaVersion: Int = PropagationCheckBlob.currentSchemaVersion,
        solarKIndex: Double? = nil,
        solarAIndex: Int? = nil,
        solarFlux: Double? = nil,
        solarSunspots: Int? = nil,
        solarPropagationRating: String? = nil,
        solarBandConditions: String? = nil,
        solarTimestamp: Date? = nil
    ) {
        self.id = id
        self.label = label
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.callsignUsed = callsignUsed
        self.userGridUsed = userGridUsed
        self.bandsRequested = bandsRequested
        self.transmitMode = transmitMode
        self.stopReason = stopReason
        self.totalSpots = totalSpots
        self.uniqueSkimmers = uniqueSkimmers
        self.bandsWithActivity = bandsWithActivity
        self.maxDistanceKm = maxDistanceKm
        self.peakSNRdB = peakSNRdB
        self.notes = notes
        self.radio = radio
        self.antenna = antenna
        self.key = key
        self.mic = mic
        self.spotsBlob = spotsBlob
        self.spotsBlobSchemaVersion = spotsBlobSchemaVersion
        self.solarKIndex = solarKIndex
        self.solarAIndex = solarAIndex
        self.solarFlux = solarFlux
        self.solarSunspots = solarSunspots
        self.solarPropagationRating = solarPropagationRating
        self.solarBandConditions = solarBandConditions
        self.solarTimestamp = solarTimestamp
    }

    // MARK: Internal

    var id = UUID()

    /// User-editable display label (e.g. "EFHW roof, 20m+40m").
    var label = ""

    var startedAt = Date()
    var endedAt = Date()

    /// Callsign used for spot matching during the session (e.g. "W6JY" or "W6JY/P").
    var callsignUsed = ""

    /// User's Maidenhead grid at session start (frozen on the artifact so future moves don't invalidate distances).
    var userGridUsed = ""

    /// Bands the user explicitly chose to watch ("20m", "40m", …).
    var bandsRequested: [String] = []

    /// Raw value of `PropagationTransmitMode`.
    var transmitMode = PropagationTransmitMode.passive.rawValue

    /// Raw value of `PropagationStopReason`.
    var stopReason = PropagationStopReason.user.rawValue

    // Denormalized headline statistics — kept in columns for fast list rendering
    // without faulting the spots blob.

    var totalSpots = 0
    var uniqueSkimmers = 0
    var bandsWithActivity: [String] = []
    var maxDistanceKm: Double = 0
    var peakSNRdB: Double = 0

    // Optional user-supplied metadata, editable on the detail view.
    var notes: String?
    var radio: String?
    var antenna: String?
    var key: String?
    var mic: String?

    /// Compressed (LZFSE) JSON of `PropagationCheckBlob`. Decode via
    /// `decodedBlob` rather than touching this directly.
    var spotsBlob = Data()

    /// Mirror of the schema version stored inside the blob, denormalized for
    /// quick filtering / migration without decompressing.
    var spotsBlobSchemaVersion = PropagationCheckBlob.currentSchemaVersion

    // Snapshot of solar / space weather conditions captured at session start.
    // Optional — records from before this field existed, or sessions that ran
    // offline, will have nil values. Mirrors the pattern on `LoggingSession`.

    var solarKIndex: Double?
    var solarAIndex: Int?
    var solarFlux: Double?
    var solarSunspots: Int?
    var solarPropagationRating: String?
    var solarBandConditions: String?
    var solarTimestamp: Date?

    // MARK: - Computed Helpers

    /// True if any solar field is present — drives optional UI rendering.
    var hasSolarData: Bool {
        solarKIndex != nil || solarFlux != nil || solarSunspots != nil
    }

    var transmitModeKind: PropagationTransmitMode {
        PropagationTransmitMode(rawValue: transmitMode) ?? .passive
    }

    var stopReasonKind: PropagationStopReason {
        PropagationStopReason(rawValue: stopReason) ?? .user
    }

    var duration: TimeInterval {
        max(0, endedAt.timeIntervalSince(startedAt))
    }

    /// Decode the spots blob lazily on detail-view open.
    var decodedBlob: PropagationCheckBlob? {
        PropagationCheckBlob.decode(from: spotsBlob)
    }

    /// Convenience: dedup key for a candidate spot. Identical keys collapse.
    nonisolated static func dedupKey(for entry: PropagationSpotEntry) -> String {
        let secondBucket = Int(entry.timestamp.timeIntervalSince1970)
        return "\(entry.source.rawValue)-\(entry.skimmerCall.uppercased())-\(entry.freqHz)-\(secondBucket)"
    }
}

// MARK: - PropagationTransmitMode

nonisolated enum PropagationTransmitMode: String, Codable, CaseIterable {
    /// User transmits via their own workflow (rig, paddle, FT8 module).
    case passive
    /// App-driven CW Auto-CQ via the radio bridge.
    case autoCW = "auto-cw"
    /// App-driven FT8 Auto-CQ via the FT8 session manager.
    case autoFT8 = "auto-ft8"

    // MARK: Internal

    var displayName: String {
        switch self {
        case .passive: "Passive"
        case .autoCW: "Auto-CQ (CW)"
        case .autoFT8: "Auto-CQ (FT8)"
        }
    }
}

// MARK: - PropagationStopReason

nonisolated enum PropagationStopReason: String, Codable, CaseIterable {
    case user
    case duration
    case radioFault = "radio-fault"
}

// MARK: - PropagationSpotSource

nonisolated enum PropagationSpotSource: String, Codable, CaseIterable {
    case rbn
    case pskr

    // MARK: Internal

    var displayName: String {
        switch self {
        case .rbn: "RBN"
        case .pskr: "PSK Reporter"
        }
    }
}

// MARK: - PropagationSpotEntry

/// A single spot collected during a propagation check.
///
/// Stored inside the opaque blob — never as a SwiftData child entity, to avoid
/// `@Query` faulting hangs at scale (see `feedback_activityitem_patterns`).
nonisolated struct PropagationSpotEntry: Codable, Hashable {
    var source: PropagationSpotSource
    var skimmerCall: String
    var skimmerGrid: String?
    var skimmerLat: Double?
    var skimmerLon: Double?
    var freqHz: Int
    var band: String?
    var mode: String
    var snrDB: Double?
    var timestamp: Date
}

// MARK: - PropagationConnectivityGap

/// A persisted record of a network outage during a session, surfaced on the
/// artifact for transparency.
nonisolated struct PropagationConnectivityGap: Codable, Hashable {
    var source: PropagationSpotSource
    var startedAt: Date
    var endedAt: Date
}

// MARK: - PropagationCheckBlob

/// The wire shape stored inside `PropagationCheck.spotsBlob`.
nonisolated struct PropagationCheckBlob: Codable {
    // MARK: Lifecycle

    init(spots: [PropagationSpotEntry] = [], connectivityGaps: [PropagationConnectivityGap] = []) {
        schemaVersion = Self.currentSchemaVersion
        self.spots = spots
        self.connectivityGaps = connectivityGaps
    }

    // MARK: Internal

    static let currentSchemaVersion = 1

    var schemaVersion: Int = PropagationCheckBlob.currentSchemaVersion
    var spots: [PropagationSpotEntry]
    var connectivityGaps: [PropagationConnectivityGap]

    // MARK: - Nonisolated Codable Helpers

    /// Decode + decompress. Tolerates uncompressed payloads for forward compat.
    nonisolated static func decode(from data: Data) -> PropagationCheckBlob? {
        guard !data.isEmpty else {
            return PropagationCheckBlob()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decompressed = (try? (data as NSData).decompressed(using: .lzfse) as Data) ?? Data()
        if !decompressed.isEmpty,
           let blob = try? decoder.decode(PropagationCheckBlob.self, from: decompressed)
        {
            return blob
        }
        return try? decoder.decode(PropagationCheckBlob.self, from: data)
    }

    /// Encode + LZFSE compress. Returns empty data on failure (matches `ActivityDetails.encode()`).
    nonisolated func encode() -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let raw = try? encoder.encode(self) else {
            return Data()
        }
        if let compressed = try? (raw as NSData).compressed(using: .lzfse) as Data {
            return compressed
        }
        return raw
    }
}

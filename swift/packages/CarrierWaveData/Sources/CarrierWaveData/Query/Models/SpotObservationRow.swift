import Foundation
import GRDB

public struct SpotObservationRow: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    // MARK: Lifecycle

    public init(
        obsId: String,
        spotId: String,
        callsign: String,
        band: String,
        mode: String,
        freqHz: Int64?,
        source: String,
        spotter: String?,
        spotLat: Double? = nil,
        spotLon: Double? = nil,
        snrDb: Int?,
        speedWpm: Int?,
        comment: String?,
        receivedAt: Date,
        priority: Int
    ) {
        self.obsId = obsId
        self.spotId = spotId
        self.callsign = callsign
        self.band = band
        self.mode = mode
        self.freqHz = freqHz
        self.source = source
        self.spotter = spotter
        self.spotLat = spotLat
        self.spotLon = spotLon
        self.snrDb = snrDb
        self.speedWpm = speedWpm
        self.comment = comment
        self.receivedAt = receivedAt
        self.priority = priority
    }

    // MARK: Public

    // Use Unix epoch seconds (REAL) for `received_at` so it matches
    // the column declaration in `ScopeSchema.swift` AND the units
    // returned by `cw_now()`, `strftime('%s', 'now')`, and the rest
    // of the schema (`scope.spots.last_seen_at`, `qsos.timestamp`).
    // GRDB's default for `Date` via Codable is a TEXT string in
    // `yyyy-MM-dd HH:mm:ss.SSS` form — incompatible with arithmetic.
    public static let databaseDateEncodingStrategy = DatabaseDateEncodingStrategy.timeIntervalSince1970
    public static let databaseDateDecodingStrategy = DatabaseDateDecodingStrategy.timeIntervalSince1970

    public static let databaseTableName = "spot_observations"

    public var obsId: String
    public var spotId: String
    public var callsign: String
    public var band: String
    public var mode: String
    public var freqHz: Int64?
    public var source: String
    public var spotter: String?
    public var spotLat: Double?
    public var spotLon: Double?
    public var snrDb: Int?
    public var speedWpm: Int?
    public var comment: String?
    public var receivedAt: Date
    public var priority: Int

    // MARK: Internal

    enum CodingKeys: String, CodingKey {
        case obsId = "obs_id"
        case spotId = "spot_id"
        case callsign
        case band
        case mode
        case freqHz = "freq_hz"
        case source
        case spotter
        case spotLat = "spot_lat"
        case spotLon = "spot_lon"
        case snrDb = "snr_db"
        case speedWpm = "speed_wpm"
        case comment
        case receivedAt = "received_at"
        case priority
    }
}

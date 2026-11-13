import Foundation
import GRDB

public struct SpotRow: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    // MARK: Lifecycle

    public init(
        spotId: String,
        callsign: String,
        band: String,
        mode: String,
        freqHz: Int64?,
        dxccEntity: String?,
        continent: String?,
        cqZone: Int?,
        ituZone: Int?,
        grid: String?,
        parkRef: String?,
        lastSeenAt: Date
    ) {
        self.spotId = spotId
        self.callsign = callsign
        self.band = band
        self.mode = mode
        self.freqHz = freqHz
        self.dxccEntity = dxccEntity
        self.continent = continent
        self.cqZone = cqZone
        self.ituZone = ituZone
        self.grid = grid
        self.parkRef = parkRef
        self.lastSeenAt = lastSeenAt
    }

    // MARK: Public

    public static let databaseTableName = "spots"

    public var spotId: String
    public var callsign: String
    public var band: String
    public var mode: String
    public var freqHz: Int64?
    public var dxccEntity: String?
    public var continent: String?
    public var cqZone: Int?
    public var ituZone: Int?
    public var grid: String?
    public var parkRef: String?
    public var lastSeenAt: Date

    // MARK: Internal

    enum CodingKeys: String, CodingKey {
        case spotId = "spot_id"
        case callsign
        case band
        case mode
        case freqHz = "freq_hz"
        case dxccEntity = "dxcc_entity"
        case continent
        case cqZone = "cq_zone"
        case ituZone = "itu_zone"
        case grid
        case parkRef = "park_ref"
        case lastSeenAt = "last_seen_at"
    }
}

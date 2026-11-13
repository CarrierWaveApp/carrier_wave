import Foundation
import GRDB

public struct DXCCRow: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    // MARK: Lifecycle

    public init(
        entity: String,
        prefix: String?,
        continent: String?,
        cqZone: Int?,
        ituZone: Int?,
        lat: Double?,
        lon: Double?
    ) {
        self.entity = entity
        self.prefix = prefix
        self.continent = continent
        self.cqZone = cqZone
        self.ituZone = ituZone
        self.lat = lat
        self.lon = lon
    }

    // MARK: Public

    public static let databaseTableName = "dxcc"

    public var entity: String
    public var prefix: String?
    public var continent: String?
    public var cqZone: Int?
    public var ituZone: Int?
    public var lat: Double?
    public var lon: Double?

    // MARK: Internal

    enum CodingKeys: String, CodingKey {
        case entity
        case prefix
        case continent
        case cqZone = "cq_zone"
        case ituZone = "itu_zone"
        case lat
        case lon
    }
}

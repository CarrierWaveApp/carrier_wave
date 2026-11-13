import Foundation
import GRDB

public struct SpotterRow: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    // MARK: Lifecycle

    public init(
        callsign: String,
        grid: String?,
        lat: Double?,
        lon: Double?,
        dxccEntity: String?,
        continent: String?,
        isSkimmer: Bool
    ) {
        self.callsign = callsign
        self.grid = grid
        self.lat = lat
        self.lon = lon
        self.dxccEntity = dxccEntity
        self.continent = continent
        self.isSkimmer = isSkimmer
    }

    // MARK: Public

    public static let databaseTableName = "spotters"

    public var callsign: String
    public var grid: String?
    public var lat: Double?
    public var lon: Double?
    public var dxccEntity: String?
    public var continent: String?
    public var isSkimmer: Bool

    // MARK: Internal

    enum CodingKeys: String, CodingKey {
        case callsign
        case grid
        case lat
        case lon
        case dxccEntity = "dxcc_entity"
        case continent
        case isSkimmer = "is_skimmer"
    }
}

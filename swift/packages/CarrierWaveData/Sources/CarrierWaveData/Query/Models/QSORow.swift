import Foundation
import GRDB

public struct QSORow: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    // MARK: Lifecycle

    public init(
        id: String,
        callsign: String,
        band: String,
        mode: String,
        frequency: Double?,
        timestamp: Date,
        myCallsign: String,
        theirGrid: String?,
        myGrid: String?,
        parkRef: String?,
        theirParkRef: String?,
        dxcc: Int?,
        modifiedAt: Date?,
        isHidden: Bool,
        isActivityLog: Bool
    ) {
        self.id = id
        self.callsign = callsign
        self.band = band
        self.mode = mode
        self.frequency = frequency
        self.timestamp = timestamp
        self.myCallsign = myCallsign
        self.theirGrid = theirGrid
        self.myGrid = myGrid
        self.parkRef = parkRef
        self.theirParkRef = theirParkRef
        self.dxcc = dxcc
        self.modifiedAt = modifiedAt
        self.isHidden = isHidden
        self.isActivityLog = isActivityLog
    }

    // MARK: Public

    public static let databaseTableName = "qsos"

    public var id: String
    public var callsign: String
    public var band: String
    public var mode: String
    public var frequency: Double?
    public var timestamp: Date
    public var myCallsign: String
    public var theirGrid: String?
    public var myGrid: String?
    public var parkRef: String?
    public var theirParkRef: String?
    public var dxcc: Int?
    public var modifiedAt: Date?
    public var isHidden: Bool
    public var isActivityLog: Bool

    // MARK: Internal

    enum CodingKeys: String, CodingKey {
        case id
        case callsign
        case band
        case mode
        case frequency
        case timestamp
        case myCallsign = "my_callsign"
        case theirGrid = "their_grid"
        case myGrid = "my_grid"
        case parkRef = "park_ref"
        case theirParkRef = "their_park_ref"
        case dxcc
        case modifiedAt = "modified_at"
        case isHidden = "is_hidden"
        case isActivityLog = "is_activity_log"
    }
}

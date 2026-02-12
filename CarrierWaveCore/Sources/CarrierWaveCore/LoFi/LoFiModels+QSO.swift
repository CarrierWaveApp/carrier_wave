import Foundation

// MARK: - LoFiQsosResponse

public struct LoFiQsosResponse: Decodable, @unchecked Sendable {
    public let qsos: [LoFiQso]
    public let meta: LoFiQsosMetaWrapper
}

// MARK: - LoFiQsosMetaWrapper

public struct LoFiQsosMetaWrapper: Decodable, @unchecked Sendable {
    public let qsos: LoFiQsosMeta
}

// MARK: - LoFiQsosMeta

public struct LoFiQsosMeta: Decodable, @unchecked Sendable {
    public enum CodingKeys: String, CodingKey {
        case totalRecords = "total_records"
        case syncedUntilMillis = "synced_until_millis"
        case syncedUntil = "synced_until"
        case syncedSinceMillis = "synced_since_millis"
        case limit
        case recordsLeft = "records_left"
        case nextUpdatedAtMillis = "next_updated_at_millis"
        case nextSyncedAtMillis = "next_synced_at_millis"
        case extendedPage = "extended_page"
        case otherClientsOnly = "other_clients_only"
    }

    public let totalRecords: Int
    public let syncedUntilMillis: Double?
    public let syncedUntil: String?
    public let syncedSinceMillis: Double?
    public let limit: Int
    public let recordsLeft: Int
    public let nextUpdatedAtMillis: Double?
    public let nextSyncedAtMillis: Double?
    public let extendedPage: Bool?
    public let otherClientsOnly: Bool?
}

// MARK: - LoFiQso

public struct LoFiQso: Decodable, @unchecked Sendable {
    // MARK: Lifecycle

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uuid = try container.decode(String.self, forKey: .uuid)
        operation = try container.decodeIfPresent(String.self, forKey: .operation)
        account = try container.decodeIfPresent(String.self, forKey: .account)
        createdAtMillis = try container.decodeIfPresent(Double.self, forKey: .createdAtMillis)
        updatedAtMillis = try container.decodeIfPresent(Double.self, forKey: .updatedAtMillis)
        syncedAtMillis = try container.decodeIfPresent(Double.self, forKey: .syncedAtMillis)
        startAtMillis = try container.decodeIfPresent(Double.self, forKey: .startAtMillis)
        their = try container.decodeIfPresent(LoFiTheirInfo.self, forKey: .their)
        our = try container.decodeIfPresent(LoFiOurInfo.self, forKey: .our)
        band = try container.decodeIfPresent(String.self, forKey: .band)
        freq = try container.decodeIfPresent(Double.self, forKey: .freq)
        mode = try container.decodeIfPresent(String.self, forKey: .mode)
        refs = try container.decodeIfPresent([LoFiQsoRef].self, forKey: .refs)
        txPwr = try container.decodeIfPresent(String.self, forKey: .txPwr)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)

        // Handle deleted field as either Int or Bool (API returns both)
        if let intValue = try? container.decodeIfPresent(Int.self, forKey: .deleted) {
            deleted = intValue
        } else if let boolValue = try? container.decodeIfPresent(Bool.self, forKey: .deleted) {
            deleted = boolValue ? 1 : 0
        } else {
            deleted = nil
        }
    }

    // MARK: Public

    public enum CodingKeys: String, CodingKey {
        case uuid
        case operation
        case account
        case createdAtMillis
        case updatedAtMillis
        case syncedAtMillis
        case startAtMillis
        case their
        case our
        case band
        case freq
        case mode
        case refs
        case txPwr
        case notes
        case deleted
    }

    public let uuid: String
    public let operation: String?
    public let account: String?
    public let createdAtMillis: Double?
    public let updatedAtMillis: Double?
    public let syncedAtMillis: Double?
    public let startAtMillis: Double?
    public let their: LoFiTheirInfo?
    public let our: LoFiOurInfo?
    public let band: String?
    public let freq: Double?
    public let mode: String?
    public let refs: [LoFiQsoRef]?
    public let txPwr: String?
    public let notes: String?
    public let deleted: Int?
}

// MARK: - LoFiTheirInfo

public struct LoFiTheirInfo: Decodable, @unchecked Sendable {
    public let call: String?
    public let sent: String?
    public let guess: LoFiGuessInfo?
}

// MARK: - LoFiOurInfo

public struct LoFiOurInfo: Decodable, @unchecked Sendable {
    public let call: String?
    public let sent: String?
}

// MARK: - LoFiGuessInfo

public struct LoFiGuessInfo: Decodable, @unchecked Sendable {
    public enum CodingKeys: String, CodingKey {
        case call
        case name
        case state
        case city
        case grid
        case country
        case entityName = "entity_name"
        case cqZone = "cq_zone"
        case ituZone = "itu_zone"
        case dxccCode = "dxcc_code"
        case continent
    }

    public let call: String?
    public let name: String?
    public let state: String?
    public let city: String?
    public let grid: String?
    public let country: String?
    public let entityName: String?
    public let cqZone: Int?
    public let ituZone: Int?
    public let dxccCode: Int?
    public let continent: String?
}

// MARK: - LoFiQsoRef

public struct LoFiQsoRef: Decodable, @unchecked Sendable {
    public enum CodingKeys: String, CodingKey {
        case refType = "type"
        case reference = "ref"
        case program
        case ourNumber = "our_number"
    }

    public let refType: String?
    public let reference: String?
    public let program: String?
    public let ourNumber: String?
}

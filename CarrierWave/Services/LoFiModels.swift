import Foundation

// MARK: - LoFiRegistrationRequest

struct LoFiRegistrationRequest: Encodable, @unchecked Sendable {
    let client: LoFiClientCredentials
    let account: LoFiAccountRequest
    let meta: LoFiMetaRequest
}

// MARK: - LoFiClientCredentials

struct LoFiClientCredentials: Encodable, @unchecked Sendable {
    let key: String
    let name: String
    let secret: String
}

// MARK: - LoFiAccountRequest

struct LoFiAccountRequest: Encodable, @unchecked Sendable {
    let call: String
}

// MARK: - LoFiMetaRequest

struct LoFiMetaRequest: Encodable, @unchecked Sendable {
    let app: String
}

// MARK: - LoFiRegistrationResponse

struct LoFiRegistrationResponse: Decodable, @unchecked Sendable {
    let token: String
    let client: LoFiClientInfo
    let account: LoFiAccountInfo
    let meta: LoFiMetaInfo
}

// MARK: - LoFiClientInfo

struct LoFiClientInfo: Decodable, @unchecked Sendable {
    let uuid: String
    let name: String
}

// MARK: - LoFiAccountInfo

struct LoFiAccountInfo: Decodable, @unchecked Sendable {
    enum CodingKeys: String, CodingKey {
        case uuid
        case call
        case name
        case email
        case cutoffDate = "cutoff_date"
        case cutoffDateMillis = "cutoff_date_millis"
    }

    let uuid: String
    let call: String
    let name: String?
    let email: String?
    let cutoffDate: String?
    let cutoffDateMillis: Int64?
}

// MARK: - LoFiMetaInfo

struct LoFiMetaInfo: Decodable, @unchecked Sendable {
    let flags: LoFiSyncFlags
}

// MARK: - LoFiSyncFlags

struct LoFiSyncFlags: Codable, @unchecked Sendable {
    enum CodingKeys: String, CodingKey {
        case suggestedSyncBatchSize = "suggested_sync_batch_size"
        case suggestedSyncLoopDelay = "suggested_sync_loop_delay"
        case suggestedSyncCheckPeriod = "suggested_sync_check_period"
    }

    static let defaults = LoFiSyncFlags(
        suggestedSyncBatchSize: 50, suggestedSyncLoopDelay: 10_000, suggestedSyncCheckPeriod: 20_000
    )

    let suggestedSyncBatchSize: Int // QSOs/operations per batch (default: 50)
    let suggestedSyncLoopDelay: Int // ms between batches (default: 10000)
    let suggestedSyncCheckPeriod: Int // ms between sync polls (default: 20000)
}

// MARK: - LoFiLinkDeviceRequest

struct LoFiLinkDeviceRequest: Encodable, @unchecked Sendable {
    let email: String
}

// MARK: - LoFiAccountsResponse

/// Response from GET /v1/accounts - includes total counts for progress display
struct LoFiAccountsResponse: Decodable, @unchecked Sendable {
    let operations: LoFiRecordCounts
    let qsos: LoFiRecordCounts
}

// MARK: - LoFiRecordCounts

/// Total and syncable counts for a record type
struct LoFiRecordCounts: Decodable, @unchecked Sendable {
    let total: Int
    let syncable: Int
}

// MARK: - LoFiOperationsResponse

struct LoFiOperationsResponse: Decodable, @unchecked Sendable {
    let operations: [LoFiOperation]
    let meta: LoFiOperationsMetaWrapper
}

// MARK: - LoFiOperationsMetaWrapper

struct LoFiOperationsMetaWrapper: Decodable, @unchecked Sendable {
    let operations: LoFiOperationsMeta
}

// MARK: - LoFiOperationsMeta

struct LoFiOperationsMeta: Decodable, @unchecked Sendable {
    enum CodingKeys: String, CodingKey {
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

    let totalRecords: Int
    let syncedUntilMillis: Double?
    let syncedUntil: String?
    let syncedSinceMillis: Double?
    let limit: Int
    let recordsLeft: Int
    let nextUpdatedAtMillis: Double?
    let nextSyncedAtMillis: Double?
    let extendedPage: Bool?
    let otherClientsOnly: Bool?
}

// MARK: - LoFiOperation

struct LoFiOperation: Decodable, @unchecked Sendable {
    // MARK: Lifecycle

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uuid = try container.decode(String.self, forKey: .uuid)
        stationCall = try container.decode(String.self, forKey: .stationCall)
        account = try container.decode(String.self, forKey: .account)
        createdAtMillis = try container.decode(Double.self, forKey: .createdAtMillis)
        createdOnDeviceId = try container.decodeIfPresent(String.self, forKey: .createdOnDeviceId)
        updatedAtMillis = try container.decodeIfPresent(Double.self, forKey: .updatedAtMillis)
        updatedOnDeviceId = try container.decodeIfPresent(String.self, forKey: .updatedOnDeviceId)
        syncedAtMillis = try container.decodeIfPresent(Double.self, forKey: .syncedAtMillis)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        grid = try container.decodeIfPresent(String.self, forKey: .grid)
        refs = try container.decodeIfPresent([LoFiOperationRef].self, forKey: .refs) ?? []
        qsoCount = try container.decode(Int.self, forKey: .qsoCount)
        startAtMillisMin = try container.decodeIfPresent(Double.self, forKey: .startAtMillisMin)
        startAtMillisMax = try container.decodeIfPresent(Double.self, forKey: .startAtMillisMax)
        isNew = try container.decodeIfPresent(Bool.self, forKey: .isNew)

        // Handle deleted field as either Int or Bool (API returns both)
        if let intValue = try? container.decodeIfPresent(Int.self, forKey: .deleted) {
            deleted = intValue
        } else if let boolValue = try? container.decodeIfPresent(Bool.self, forKey: .deleted) {
            deleted = boolValue ? 1 : 0
        } else {
            deleted = nil
        }

        // Handle synced field as either Int or Bool (API may return both)
        if let intValue = try? container.decodeIfPresent(Int.self, forKey: .synced) {
            synced = intValue
        } else if let boolValue = try? container.decodeIfPresent(Bool.self, forKey: .synced) {
            synced = boolValue ? 1 : 0
        } else {
            synced = nil
        }
    }

    // MARK: Internal

    enum CodingKeys: String, CodingKey {
        case uuid
        case stationCall
        case account
        case createdAtMillis
        case createdOnDeviceId
        case updatedAtMillis
        case updatedOnDeviceId
        case syncedAtMillis
        case title
        case subtitle
        case grid
        case refs
        case qsoCount
        case startAtMillisMin
        case startAtMillisMax
        case isNew
        case deleted
        case synced
    }

    let uuid: String
    let stationCall: String
    let account: String
    let createdAtMillis: Double
    let createdOnDeviceId: String?
    let updatedAtMillis: Double?
    let updatedOnDeviceId: String?
    let syncedAtMillis: Double?
    let title: String?
    let subtitle: String?
    let grid: String?
    let refs: [LoFiOperationRef]
    let qsoCount: Int
    let startAtMillisMin: Double?
    let startAtMillisMax: Double?
    let isNew: Bool?
    let deleted: Int?
    let synced: Int?
}

// MARK: - LoFiOperationRef

struct LoFiOperationRef: Decodable, @unchecked Sendable {
    enum CodingKeys: String, CodingKey {
        case refType = "type"
        case reference = "ref"
        case name, location, label
        case shortLabel = "short_label"
        case program
    }

    let refType: String
    let reference: String?
    let name: String?
    let location: String?
    let label: String?
    let shortLabel: String?
    let program: String?
}

extension LoFiOperation {
    var potaRef: LoFiOperationRef? {
        refs.first { $0.refType == "potaActivation" || $0.program == "POTA" }
    }

    var sotaRef: LoFiOperationRef? {
        refs.first { $0.refType == "sotaActivation" || $0.program == "SOTA" }
    }
}

// MARK: - LoFiQsosResponse

struct LoFiQsosResponse: Decodable, @unchecked Sendable {
    let qsos: [LoFiQso]
    let meta: LoFiQsosMetaWrapper
}

// MARK: - LoFiQsosMetaWrapper

struct LoFiQsosMetaWrapper: Decodable, @unchecked Sendable {
    let qsos: LoFiQsosMeta
}

// MARK: - LoFiQsosMeta

struct LoFiQsosMeta: Decodable, @unchecked Sendable {
    enum CodingKeys: String, CodingKey {
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

    let totalRecords: Int
    let syncedUntilMillis: Double?
    let syncedUntil: String?
    let syncedSinceMillis: Double?
    let limit: Int
    let recordsLeft: Int
    let nextUpdatedAtMillis: Double?
    let nextSyncedAtMillis: Double?
    let extendedPage: Bool?
    let otherClientsOnly: Bool?
}

// MARK: - LoFiQso

struct LoFiQso: Decodable, @unchecked Sendable {
    // MARK: Lifecycle

    init(from decoder: Decoder) throws {
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

    // MARK: Internal

    enum CodingKeys: String, CodingKey {
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

    let uuid: String
    let operation: String?
    let account: String?
    let createdAtMillis: Double?
    let updatedAtMillis: Double?
    let syncedAtMillis: Double?
    let startAtMillis: Double?
    let their: LoFiTheirInfo?
    let our: LoFiOurInfo?
    let band: String?
    let freq: Double? // kHz
    let mode: String?
    let refs: [LoFiQsoRef]?
    let txPwr: String?
    let notes: String?
    let deleted: Int?
}

// MARK: - LoFiTheirInfo

struct LoFiTheirInfo: Decodable, @unchecked Sendable {
    let call: String?
    let sent: String?
    let guess: LoFiGuessInfo?
}

// MARK: - LoFiOurInfo

struct LoFiOurInfo: Decodable, @unchecked Sendable {
    let call: String?
    let sent: String?
}

// MARK: - LoFiGuessInfo

struct LoFiGuessInfo: Decodable, @unchecked Sendable {
    enum CodingKeys: String, CodingKey {
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

    let call: String?
    let name: String?
    let state: String?
    let city: String?
    let grid: String?
    let country: String?
    let entityName: String?
    let cqZone: Int?
    let ituZone: Int?
    let dxccCode: Int?
    let continent: String?
}

// MARK: - LoFiQsoRef

struct LoFiQsoRef: Decodable, @unchecked Sendable {
    enum CodingKeys: String, CodingKey {
        case refType = "type"
        case reference = "ref"
        case program
        case ourNumber = "our_number"
    }

    let refType: String?
    let reference: String?
    let program: String?
    let ourNumber: String?
}

// MARK: - QSO Helpers

extension LoFiQso {
    var theirCall: String? {
        their?.call
    }

    var ourCall: String? {
        our?.call
    }

    var rstSent: String? {
        our?.sent
    }

    var rstRcvd: String? {
        their?.sent
    }

    var theirGrid: String? {
        their?.guess?.grid
    }

    var theirName: String? {
        their?.guess?.name
    }

    var theirState: String? {
        their?.guess?.state
    }

    var theirCountry: String? {
        their?.guess?.entityName
    }

    /// Frequency in MHz (API returns kHz)
    var freqMHz: Double? {
        freq.map { $0 / 1_000.0 }
    }

    /// QSO timestamp as Date (returns nil if startAtMillis is missing)
    var timestamp: Date? {
        startAtMillis.map { Date(timeIntervalSince1970: $0 / 1_000.0) }
    }

    /// Get their POTA reference
    var theirPotaRef: String? {
        refs?.first { $0.refType == "pota" || $0.program == "POTA" }?.reference
    }

    /// Get our POTA reference from operation refs
    func myPotaRef(from operationRefs: [LoFiOperationRef]) -> String? {
        operationRefs
            .first { $0.refType == "potaActivation" }?
            .reference
    }
}

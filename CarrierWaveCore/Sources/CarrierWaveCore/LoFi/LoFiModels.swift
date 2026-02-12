import Foundation

// MARK: - LoFiRegistrationRequest

public struct LoFiRegistrationRequest: Encodable, @unchecked Sendable {
    // MARK: Lifecycle

    public init(client: LoFiClientCredentials, account: LoFiAccountRequest, meta: LoFiMetaRequest) {
        self.client = client
        self.account = account
        self.meta = meta
    }

    // MARK: Public

    public let client: LoFiClientCredentials
    public let account: LoFiAccountRequest
    public let meta: LoFiMetaRequest
}

// MARK: - LoFiClientCredentials

public struct LoFiClientCredentials: Encodable, @unchecked Sendable {
    // MARK: Lifecycle

    public init(key: String, name: String, secret: String) {
        self.key = key
        self.name = name
        self.secret = secret
    }

    // MARK: Public

    public let key: String
    public let name: String
    public let secret: String
}

// MARK: - LoFiAccountRequest

public struct LoFiAccountRequest: Encodable, @unchecked Sendable {
    // MARK: Lifecycle

    public init(call: String) {
        self.call = call
    }

    // MARK: Public

    public let call: String
}

// MARK: - LoFiMetaRequest

public struct LoFiMetaRequest: Encodable, @unchecked Sendable {
    // MARK: Lifecycle

    public init(app: String) {
        self.app = app
    }

    // MARK: Public

    public let app: String
}

// MARK: - LoFiRegistrationResponse

public struct LoFiRegistrationResponse: Decodable, @unchecked Sendable {
    public let token: String
    public let client: LoFiClientInfo
    public let account: LoFiAccountInfo
    public let meta: LoFiMetaInfo
}

// MARK: - LoFiClientInfo

public struct LoFiClientInfo: Decodable, @unchecked Sendable {
    public let uuid: String
    public let name: String
}

// MARK: - LoFiAccountInfo

public struct LoFiAccountInfo: Decodable, @unchecked Sendable {
    public enum CodingKeys: String, CodingKey {
        case uuid
        case call
        case name
        case email
        case cutoffDate = "cutoff_date"
        case cutoffDateMillis = "cutoff_date_millis"
    }

    public let uuid: String
    public let call: String
    public let name: String?
    public let email: String?
    public let cutoffDate: String?
    public let cutoffDateMillis: Int64?
}

// MARK: - LoFiMetaInfo

public struct LoFiMetaInfo: Decodable, @unchecked Sendable {
    public let flags: LoFiSyncFlags
}

// MARK: - LoFiSyncFlags

public struct LoFiSyncFlags: Codable, @unchecked Sendable {
    // MARK: Lifecycle

    public init(
        suggestedSyncBatchSize: Int,
        suggestedSyncLoopDelay: Int,
        suggestedSyncCheckPeriod: Int
    ) {
        self.suggestedSyncBatchSize = suggestedSyncBatchSize
        self.suggestedSyncLoopDelay = suggestedSyncLoopDelay
        self.suggestedSyncCheckPeriod = suggestedSyncCheckPeriod
    }

    // MARK: Public

    public enum CodingKeys: String, CodingKey {
        case suggestedSyncBatchSize = "suggested_sync_batch_size"
        case suggestedSyncLoopDelay = "suggested_sync_loop_delay"
        case suggestedSyncCheckPeriod = "suggested_sync_check_period"
    }

    public static let defaults = LoFiSyncFlags(
        suggestedSyncBatchSize: 50, suggestedSyncLoopDelay: 10_000, suggestedSyncCheckPeriod: 20_000
    )

    public let suggestedSyncBatchSize: Int
    public let suggestedSyncLoopDelay: Int
    public let suggestedSyncCheckPeriod: Int
}

// MARK: - LoFiLinkDeviceRequest

public struct LoFiLinkDeviceRequest: Encodable, @unchecked Sendable {
    // MARK: Lifecycle

    public init(email: String) {
        self.email = email
    }

    // MARK: Public

    public let email: String
}

// MARK: - LoFiAccountsResponse

/// Response from GET /v1/accounts - includes total counts for progress display
public struct LoFiAccountsResponse: Decodable, @unchecked Sendable {
    public let operations: LoFiRecordCounts
    public let qsos: LoFiRecordCounts
}

// MARK: - LoFiRecordCounts

/// Total and syncable counts for a record type
public struct LoFiRecordCounts: Decodable, @unchecked Sendable {
    public let total: Int
    public let syncable: Int
}

// MARK: - LoFiOperationsResponse

public struct LoFiOperationsResponse: Decodable, @unchecked Sendable {
    public let operations: [LoFiOperation]
    public let meta: LoFiOperationsMetaWrapper
}

// MARK: - LoFiOperationsMetaWrapper

public struct LoFiOperationsMetaWrapper: Decodable, @unchecked Sendable {
    public let operations: LoFiOperationsMeta
}

// MARK: - LoFiOperationsMeta

public struct LoFiOperationsMeta: Decodable, @unchecked Sendable {
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

// MARK: - LoFiOperation

public struct LoFiOperation: Decodable, @unchecked Sendable {
    // MARK: Lifecycle

    public init(from decoder: Decoder) throws {
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

    // MARK: Public

    public enum CodingKeys: String, CodingKey {
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

    public let uuid: String
    public let stationCall: String
    public let account: String
    public let createdAtMillis: Double
    public let createdOnDeviceId: String?
    public let updatedAtMillis: Double?
    public let updatedOnDeviceId: String?
    public let syncedAtMillis: Double?
    public let title: String?
    public let subtitle: String?
    public let grid: String?
    public let refs: [LoFiOperationRef]
    public let qsoCount: Int
    public let startAtMillisMin: Double?
    public let startAtMillisMax: Double?
    public let isNew: Bool?
    public let deleted: Int?
    public let synced: Int?
}

// MARK: - LoFiOperationRef

public struct LoFiOperationRef: Decodable, @unchecked Sendable {
    // MARK: Lifecycle

    public init(
        refType: String,
        reference: String?,
        name: String?,
        location: String?,
        label: String?,
        shortLabel: String?,
        program: String?
    ) {
        self.refType = refType
        self.reference = reference
        self.name = name
        self.location = location
        self.label = label
        self.shortLabel = shortLabel
        self.program = program
    }

    // MARK: Public

    public enum CodingKeys: String, CodingKey {
        case refType = "type"
        case reference = "ref"
        case name, location, label
        case shortLabel = "short_label"
        case program
    }

    public let refType: String
    public let reference: String?
    public let name: String?
    public let location: String?
    public let label: String?
    public let shortLabel: String?
    public let program: String?
}

public extension LoFiOperation {
    var potaRefs: [LoFiOperationRef] {
        refs.filter { $0.refType == "potaActivation" || $0.program == "POTA" }
    }

    var potaRef: LoFiOperationRef? {
        potaRefs.first
    }

    var potaParkReference: String? {
        let parks = potaRefs.compactMap(\.reference)
        return parks.isEmpty ? nil : parks.joined(separator: ", ")
    }

    var sotaRef: LoFiOperationRef? {
        refs.first { $0.refType == "sotaActivation" || $0.program == "SOTA" }
    }
}

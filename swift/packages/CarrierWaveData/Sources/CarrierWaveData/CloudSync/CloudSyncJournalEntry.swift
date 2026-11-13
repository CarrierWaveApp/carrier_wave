import CloudKit
import Foundation

// MARK: - JournalEntityType

/// Entity types tracked in journal entries.
public enum JournalEntityType: String, Codable, Sendable {
    case qso
    case servicePresence
    case loggingSession
    case activationMetadata
    case sessionSpot
    case activityLog
    case radioMacro
}

// MARK: - JournalOperation

/// A single change operation within a journal entry.
/// Uses the existing Codable field structs for type-safe serialization.
public enum JournalOperation: Codable, Sendable {
    case upsertQSO(QSOFields)
    case upsertServicePresence(ServicePresenceFields)
    case upsertLoggingSession(LoggingSessionFields)
    case upsertActivationMetadata(ActivationMetadataFields)
    case upsertSessionSpot(SessionSpotFields)
    case upsertActivityLog(ActivityLogFields)
    case upsertRadioMacro(RadioMacroFields)
    case delete(entityType: JournalEntityType, id: UUID)

    // MARK: Public

    public var entityType: JournalEntityType {
        switch self {
        case .upsertQSO: .qso
        case .upsertServicePresence: .servicePresence
        case .upsertLoggingSession: .loggingSession
        case .upsertActivationMetadata: .activationMetadata
        case .upsertSessionSpot: .sessionSpot
        case .upsertActivityLog: .activityLog
        case .upsertRadioMacro: .radioMacro
        case let .delete(entityType, _): entityType
        }
    }

    public var entityId: UUID? {
        switch self {
        case let .upsertQSO(fields): fields.id
        case let .upsertServicePresence(fields): fields.id
        case let .upsertLoggingSession(fields): fields.id
        case .upsertActivationMetadata: nil
        case let .upsertSessionSpot(fields): fields.id
        case let .upsertActivityLog(fields): fields.id
        case let .upsertRadioMacro(fields): fields.id
        case let .delete(_, id): id
        }
    }

    /// The `modifiedAt` carried by the snapshot at the moment the outbound
    /// batch was constructed. Used by the outbound dirty-flag clearer to
    /// detect "the user edited this entity between snapshot and CKRecord-save
    /// confirmation" and skip the clear so the new edit still flushes. Nil
    /// for entities without a modifiedAt field. See CAR-245.
    public var entityModifiedAt: Date? {
        switch self {
        case let .upsertQSO(fields): fields.modifiedAt
        case let .upsertRadioMacro(fields): fields.modifiedAt
        case .upsertServicePresence,
             .upsertLoggingSession,
             .upsertActivationMetadata,
             .upsertSessionSpot,
             .upsertActivityLog,
             .delete:
            nil
        }
    }
}

// MARK: - JournalPayload

/// The JSON payload stored in a single ChangeJournal CKRecord.
/// Batches multiple operations into one CloudKit record.
public struct JournalPayload: Codable, Sendable {
    // MARK: Lifecycle

    public init(
        deviceId: String,
        sequenceNumber: Int64,
        operations: [JournalOperation]
    ) {
        id = UUID()
        self.deviceId = deviceId
        timestamp = Date()
        self.sequenceNumber = sequenceNumber
        self.operations = operations
    }

    // MARK: Public

    public let id: UUID
    public let deviceId: String
    public let timestamp: Date
    public let sequenceNumber: Int64
    public let operations: [JournalOperation]
}

// MARK: - CKRecord Helpers

extension JournalPayload {
    static let recordType = "ChangeJournal"
    static let maxOperationsPerEntry = 100

    /// Encode this payload as a compressed JSON CKRecord.
    func toCKRecord() -> CKRecord {
        let recordID = CKRecord.ID(
            recordName: "Journal-\(id.uuidString)",
            zoneID: CloudSyncZone.zoneID
        )
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        if let data = try? encoder.encode(self) {
            record["payload"] = data as CKRecordValue
            record["timestamp"] = timestamp as CKRecordValue
            record["deviceId"] = deviceId as CKRecordValue
            record["sequenceNumber"] = sequenceNumber as CKRecordValue
        }
        return record
    }

    /// Decode a journal payload from a CKRecord.
    static func from(record: CKRecord) -> JournalPayload? {
        guard let data = record["payload"] as? Data else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(JournalPayload.self, from: data)
    }
}

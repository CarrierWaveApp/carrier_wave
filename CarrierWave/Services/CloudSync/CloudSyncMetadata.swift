import CloudKit
import Foundation
import SwiftData

/// Tracks per-record sync state between SwiftData and CloudKit.
/// Stores the CKRecord system fields (change tag, etc.) needed for conflict detection.
@Model
final class CloudSyncMetadata {
    // MARK: Lifecycle

    init(
        entityType: String,
        localId: UUID,
        recordName: String,
        encodedSystemFields: Data? = nil,
        lastSyncedAt: Date? = nil
    ) {
        self.entityType = entityType
        self.localId = localId
        self.recordName = recordName
        self.encodedSystemFields = encodedSystemFields
        self.lastSyncedAt = lastSyncedAt
    }

    // MARK: Internal

    /// The model type (e.g., "QSO", "ServicePresence", "LoggingSession")
    var entityType: String = ""

    /// The local SwiftData model's UUID
    var localId = UUID()

    /// The CKRecord.ID name (e.g., "QSO-A1B2C3D4-...")
    var recordName: String = ""

    /// Archived CKRecord system fields for change tag tracking.
    /// Encoded via NSKeyedArchiver from a skeleton CKRecord.
    var encodedSystemFields: Data?

    /// When this record was last successfully synced
    var lastSyncedAt: Date?

    /// Encode a CKRecord's system fields for storage
    nonisolated static func encodeSystemFields(of record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    // MARK: - Helpers

    /// Decode the stored system fields back into a skeleton CKRecord.
    /// Returns nil if no system fields are stored.
    nonisolated func decodedRecord() -> CKRecord? {
        guard let data = encodedSystemFields else {
            return nil
        }
        let coder = try? NSKeyedUnarchiver(forReadingFrom: data)
        coder?.requiresSecureCoding = true
        guard let coder else {
            return nil
        }
        let record = CKRecord(coder: coder)
        coder.finishDecoding()
        return record
    }
}

import Foundation
import SwiftData

/// Tracks per-record sync state between SwiftData and CloudKit.
/// Stores the CKRecord system fields (change tag, etc.) needed for conflict detection.
@Model
nonisolated final class CloudSyncMetadata {
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
}

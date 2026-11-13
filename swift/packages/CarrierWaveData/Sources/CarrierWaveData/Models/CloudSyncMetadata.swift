import Foundation
import SwiftData

@Model
nonisolated public final class CloudSyncMetadata {
    // MARK: Lifecycle

    public init(
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

    // MARK: Public

    public var entityType: String = ""
    public var localId = UUID()
    public var recordName: String = ""
    public var encodedSystemFields: Data?
    public var lastSyncedAt: Date?
}

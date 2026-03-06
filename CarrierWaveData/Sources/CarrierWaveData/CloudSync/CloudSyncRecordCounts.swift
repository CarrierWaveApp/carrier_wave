import Foundation

/// Snapshot of dirty and synced record counts for the iCloud sync status UI.
public struct CloudSyncRecordCounts: Sendable {
    // MARK: Lifecycle

    public init(
        dirtyQSOs: Int,
        dirtyServicePresence: Int,
        dirtySessions: Int,
        dirtyMetadata: Int,
        dirtySpots: Int,
        dirtyLogs: Int,
        syncedRecords: [String: Int]
    ) {
        self.dirtyQSOs = dirtyQSOs
        self.dirtyServicePresence = dirtyServicePresence
        self.dirtySessions = dirtySessions
        self.dirtyMetadata = dirtyMetadata
        self.dirtySpots = dirtySpots
        self.dirtyLogs = dirtyLogs
        self.syncedRecords = syncedRecords
    }

    // MARK: Public

    public static let empty = CloudSyncRecordCounts(
        dirtyQSOs: 0, dirtyServicePresence: 0, dirtySessions: 0,
        dirtyMetadata: 0, dirtySpots: 0, dirtyLogs: 0,
        syncedRecords: [:]
    )

    public let dirtyQSOs: Int
    public let dirtyServicePresence: Int
    public let dirtySessions: Int
    public let dirtyMetadata: Int
    public let dirtySpots: Int
    public let dirtyLogs: Int
    /// Per-entity-type count of records with sync metadata (i.e., known to iCloud).
    public let syncedRecords: [String: Int]

    public var totalDirty: Int {
        dirtyQSOs + dirtyServicePresence + dirtySessions
            + dirtyMetadata + dirtySpots + dirtyLogs
    }

    public var totalSynced: Int {
        syncedRecords.values.reduce(0, +)
    }
}

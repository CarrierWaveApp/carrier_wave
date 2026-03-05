import Foundation

/// Snapshot of dirty and synced record counts for the iCloud sync status UI.
struct CloudSyncRecordCounts: Sendable {
    static let empty = CloudSyncRecordCounts(
        dirtyQSOs: 0, dirtyServicePresence: 0, dirtySessions: 0,
        dirtyMetadata: 0, dirtySpots: 0, dirtyLogs: 0,
        syncedRecords: [:]
    )

    let dirtyQSOs: Int
    let dirtyServicePresence: Int
    let dirtySessions: Int
    let dirtyMetadata: Int
    let dirtySpots: Int
    let dirtyLogs: Int
    /// Per-entity-type count of records with sync metadata (i.e., known to iCloud).
    let syncedRecords: [String: Int]

    var totalDirty: Int {
        dirtyQSOs + dirtyServicePresence + dirtySessions
            + dirtyMetadata + dirtySpots + dirtyLogs
    }

    var totalSynced: Int {
        syncedRecords.values.reduce(0, +)
    }
}

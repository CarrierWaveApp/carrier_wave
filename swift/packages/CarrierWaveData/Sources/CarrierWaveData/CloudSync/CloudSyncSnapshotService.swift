import CloudKit
import Foundation
import OSLog
import SQLite3
import SwiftData

// MARK: - CloudSyncSnapshotService

/// Handles SQLite database snapshot upload and download via CloudKit CKAssets.
/// Used for fast initial device bootstrap instead of syncing 200K individual records.
public actor CloudSyncSnapshotService {
    // MARK: Lifecycle

    public init(container: ModelContainer) {
        self.container = container
    }

    // MARK: Public

    /// Result of a snapshot upload with telemetry.
    public struct UploadResult: Sendable {
        public let fileSize: Int64
        public let duration: TimeInterval
        public let qsoCount: Int
    }

    /// Result of a snapshot download with telemetry.
    public struct DownloadResult: Sendable {
        public let fileURL: URL
        public let fileSize: Int64
        public let duration: TimeInterval
        public let qsoCount: Int
    }

    /// Upload a SQLite snapshot to CloudKit as a CKAsset.
    /// Checkpoints WAL, copies the database, and uploads as a single CKRecord.
    /// Refuses to upload if qsoCount is zero to prevent poisoning bootstrap.
    @discardableResult
    public func uploadSnapshot(storeURL: URL, qsoCount: Int) async throws -> UploadResult {
        guard qsoCount > 0 else {
            logger.warning("Refusing to upload snapshot with 0 QSOs")
            throw SnapshotError.emptyDatabase
        }
        let startTime = ContinuousClock.now
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("snapshot_\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let snapshotURL = tempDir.appendingPathComponent("database.sqlite")
        try checkpointAndCopy(storeURL: storeURL, to: snapshotURL)

        let fileSize = (try? FileManager.default.attributesOfItem(
            atPath: snapshotURL.path
        )[.size] as? Int64) ?? 0

        let asset = CKAsset(fileURL: snapshotURL)
        let record = CKRecord(
            recordType: Self.recordType,
            recordID: snapshotRecordID()
        )
        record["asset"] = asset
        record["deviceId"] = deviceId as CKRecordValue
        record["timestamp"] = Date() as CKRecordValue
        record["qsoCount"] = qsoCount as CKRecordValue
        record["schemaVersion"] = Self.schemaVersion as CKRecordValue
        record["fileSize"] = fileSize as CKRecordValue

        let database = ckDatabase()
        // Use .allKeys save policy so we unconditionally overwrite the
        // device's previous snapshot record. Without this CloudKit rejects
        // the second upload with "record to insert already exists" because
        // we never persist the prior record's `recordChangeTag` between
        // launches — and a rejected upload never sets `lastUploadDate`,
        // which would put us in a retry-storm on every fetch-finish event.
        try await modifyRecord(record, in: database)
        lastUploadDate = Date()
        UserDefaults.standard.set(
            lastUploadDate?.timeIntervalSince1970 ?? 0,
            forKey: "cloudSyncLastSnapshotUpload"
        )
        let elapsed = ContinuousClock.now - startTime
        let seconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18
        logger.info(
            "Snapshot uploaded: \(qsoCount) QSOs, \(fileSize) bytes, \(seconds)s, record=\(record.recordID.recordName)"
        )
        return UploadResult(
            fileSize: fileSize, duration: seconds, qsoCount: qsoCount
        )
    }

    /// Check if a remote snapshot exists and return its metadata.
    public func remoteSnapshotInfo() async -> SnapshotInfo? {
        let query = CKQuery(
            recordType: Self.recordType,
            predicate: NSPredicate(value: true)
        )
        query.sortDescriptors = [
            NSSortDescriptor(key: "timestamp", ascending: false),
        ]
        do {
            let (results, _) = try await ckDatabase().records(
                matching: query,
                inZoneWith: CloudSyncZone.zoneID,
                resultsLimit: 1
            )
            guard let (_, result) = results.first,
                  let record = try? result.get()
            else {
                return nil
            }
            return SnapshotInfo(
                deviceId: record["deviceId"] as? String ?? "unknown",
                timestamp: record["timestamp"] as? Date ?? record.creationDate ?? Date(),
                qsoCount: record["qsoCount"] as? Int ?? 0,
                schemaVersion: record["schemaVersion"] as? Int ?? 1,
                fileSize: record["fileSize"] as? Int64 ?? 0
            )
        } catch {
            logger.warning("Failed to query snapshot: \(error.localizedDescription)")
            return nil
        }
    }

    /// Download the latest snapshot and return the local file URL with telemetry.
    /// The caller is responsible for replacing the database and cleaning up the file.
    public func downloadSnapshot() async throws -> DownloadResult {
        let startTime = ContinuousClock.now
        let query = CKQuery(
            recordType: Self.recordType,
            predicate: NSPredicate(value: true)
        )
        query.sortDescriptors = [
            NSSortDescriptor(key: "timestamp", ascending: false),
        ]
        let (results, _) = try await ckDatabase().records(
            matching: query,
            inZoneWith: CloudSyncZone.zoneID,
            desiredKeys: ["asset", "timestamp", "qsoCount"],
            resultsLimit: 1
        )
        guard let (_, result) = results.first,
              let record = try? result.get(),
              let asset = record["asset"] as? CKAsset,
              let assetURL = asset.fileURL
        else {
            throw SnapshotError.noSnapshotAvailable
        }

        let destDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("snapshot_download_\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: destDir, withIntermediateDirectories: true
        )
        let destURL = destDir.appendingPathComponent("database.sqlite")
        try FileManager.default.copyItem(at: assetURL, to: destURL)

        let fileSize = (try? FileManager.default.attributesOfItem(
            atPath: destURL.path
        )[.size] as? Int64) ?? 0
        let count = record["qsoCount"] as? Int ?? 0
        let elapsed = ContinuousClock.now - startTime
        let seconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18
        logger.info("Snapshot downloaded: \(count) QSOs, \(fileSize) bytes, \(seconds)s")
        return DownloadResult(
            fileURL: destURL, fileSize: fileSize,
            duration: seconds, qsoCount: count
        )
    }

    /// Whether enough time has passed since last upload to warrant a new snapshot.
    public func shouldUploadSnapshot() -> Bool {
        guard let last = lastUploadDate else {
            return true
        }
        return Date().timeIntervalSince(last) > Self.uploadIntervalSeconds
    }

    // MARK: Internal

    static let recordType = "DatabaseSnapshot"
    static let schemaVersion = 1
    static let uploadIntervalSeconds: TimeInterval = 6 * 3_600 // 6 hours

    // MARK: Private

    private let container: ModelContainer
    private let logger = Logger(
        subsystem: "com.jsvana.FullDuplex", category: "SnapshotSync"
    )
    private var lastUploadDate: Date? = {
        let interval = UserDefaults.standard.double(
            forKey: "cloudSyncLastSnapshotUpload"
        )
        return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
    }()

    private var deviceId: String {
        if let existing = UserDefaults.standard.string(
            forKey: "cloudSyncDeviceId"
        ) {
            return existing
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: "cloudSyncDeviceId")
        return newId
    }

    private func snapshotRecordID() -> CKRecord.ID {
        CKRecord.ID(
            recordName: "Snapshot-\(deviceId)",
            zoneID: CloudSyncZone.zoneID
        )
    }

    private func ckDatabase() -> CKDatabase {
        CKContainer(
            identifier: "iCloud.com.jsvana.FullDuplex"
        ).privateCloudDatabase
    }

    /// Save a record using `.allKeys` policy — unconditionally overwrites
    /// any existing record at the same `recordID` regardless of its
    /// `recordChangeTag`. Wraps `CKModifyRecordsOperation` in an async API.
    private func modifyRecord(
        _ record: CKRecord, in database: CKDatabase
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            let op = CKModifyRecordsOperation(
                recordsToSave: [record], recordIDsToDelete: nil
            )
            op.savePolicy = .allKeys
            op.qualityOfService = .userInitiated
            op.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(op)
        }
    }

    private func checkpointAndCopy(storeURL: URL, to destURL: URL) throws {
        var db: OpaquePointer?
        let rc = sqlite3_open_v2(
            storeURL.path, &db, SQLITE_OPEN_READWRITE, nil
        )
        defer { sqlite3_close(db) }
        guard rc == SQLITE_OK else {
            throw SnapshotError.checkpointFailed(rc)
        }
        let wal = sqlite3_wal_checkpoint_v2(
            db, nil, SQLITE_CHECKPOINT_TRUNCATE, nil, nil
        )
        guard wal == SQLITE_OK else {
            throw SnapshotError.checkpointFailed(wal)
        }
        try FileManager.default.copyItem(at: storeURL, to: destURL)
    }
}

// MARK: - SnapshotInfo

public struct SnapshotInfo: Sendable {
    public let deviceId: String
    public let timestamp: Date
    public let qsoCount: Int
    public let schemaVersion: Int
    public let fileSize: Int64
}

// MARK: - SnapshotError

public enum SnapshotError: LocalizedError {
    case noSnapshotAvailable
    case checkpointFailed(Int32)
    case incompatibleSchema(Int)
    case emptyDatabase

    // MARK: Public

    public var errorDescription: String? {
        switch self {
        case .noSnapshotAvailable:
            "No database snapshot is available in iCloud."
        case let .checkpointFailed(code):
            "WAL checkpoint failed with code \(code)."
        case let .incompatibleSchema(version):
            "Snapshot schema version \(version) is not compatible."
        case .emptyDatabase:
            "Refusing to upload snapshot with zero QSOs."
        }
    }
}

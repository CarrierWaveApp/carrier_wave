import Foundation
import os
import SQLite3
import SwiftData

// MARK: - BackupTrigger

enum BackupTrigger: String, Codable, Sendable {
    case launch
    case preSync
    case preImport
    case manual
    case preRestore
}

// MARK: - BackupLocation

enum BackupLocation: String, Codable, Sendable {
    case local
    case icloud
}

// MARK: - BackupEntry

struct BackupEntry: Codable, Sendable, Identifiable {
    let id: UUID
    let timestamp: Date
    let trigger: BackupTrigger
    let qsoCount: Int
    let sizeBytes: Int64
    let appVersion: String
    let location: BackupLocation
    let filename: String
}

// MARK: - BackupError

enum BackupError: LocalizedError {
    case storeNotFound
    case checkpointFailed(Int32)
    case integrityCheckFailed(String)
    case backupFileNotFound
    case restoreInProgress
    case manifestCorrupted

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .storeNotFound:
            "Could not locate the database file."
        case let .checkpointFailed(code):
            "WAL checkpoint failed with code \(code)."
        case let .integrityCheckFailed(detail):
            "Database integrity check failed: \(detail)"
        case .backupFileNotFound:
            "The backup file could not be found."
        case .restoreInProgress:
            "A restore is already in progress."
        case .manifestCorrupted:
            "The backup manifest is corrupted."
        }
    }
}

// MARK: - PendingRestore

nonisolated struct PendingRestore: Codable, Sendable {
    let backupFilename: String
    let backupTimestamp: Date
    let stagedAt: Date
}

// MARK: - BackupService

/// Database backup actor: rolling snapshots, manifest,
/// retention pruning, restore, and iCloud Drive sync.
///
/// Restore and iCloud logic in BackupService+Restore.swift.
actor BackupService {
    // MARK: Internal

    static let shared = BackupService()

    nonisolated static var pendingRestoreURL: URL {
        let library = FileManager.default.urls(
            for: .libraryDirectory, in: .userDomainMask
        ).first!
        return library.appendingPathComponent("pendingRestore.json")
    }

    let maxLocalBackups = 5
    let maxICloudBackups = 2
    let logger = Logger(
        subsystem: "com.carrierwave",
        category: "BackupService"
    )

    // MARK: - Directories

    var localBackupDir: URL {
        let library = FileManager.default.urls(
            for: .libraryDirectory, in: .userDomainMask
        ).first!
        return library.appendingPathComponent("Backups")
    }

    var manifestURL: URL {
        localBackupDir.appendingPathComponent("backups.json")
    }

    var icloudBackupDir: URL? {
        guard let container = FileManager.default.url(
            forUbiquityContainerIdentifier: nil
        ) else {
            return nil
        }
        return container
            .appendingPathComponent("Documents")
            .appendingPathComponent("Backups")
    }

    // MARK: - Snapshot

    /// Create a snapshot of the database
    @discardableResult
    func snapshot(
        trigger: BackupTrigger,
        storeURL: URL
    ) async -> BackupEntry? {
        do {
            ensureBackupDirectory()
            try checkpointWAL(storeURL: storeURL)

            let entry = try createSnapshotFile(
                trigger: trigger, storeURL: storeURL
            )

            var manifest = loadManifest()
            manifest.append(entry)
            saveManifest(manifest)
            pruneLocal()
            syncToICloud()

            logger.info(
                "Backup: \(entry.filename) (\(entry.qsoCount) QSOs, \(entry.sizeBytes) bytes, \(trigger.rawValue))"
            )
            return entry
        } catch {
            logger.error(
                "Backup failed: \(error.localizedDescription)"
            )
            return nil
        }
    }

    /// List all available backups (local + iCloud), newest first
    func availableBackups() -> [BackupEntry] {
        var entries = loadManifest()
        for entry in loadICloudBackups()
            where !entries.contains(where: { $0.filename == entry.filename })
        {
            entries.append(entry)
        }
        return entries.sorted { $0.timestamp > $1.timestamp }
    }

    func urlForEntry(_ entry: BackupEntry) -> URL {
        if entry.location == .icloud,
           let dir = icloudBackupDir
        {
            return dir.appendingPathComponent(entry.filename)
        }
        return localBackupDir.appendingPathComponent(entry.filename)
    }

    // MARK: - Manifest

    func loadManifest() -> [BackupEntry] {
        guard FileManager.default.fileExists(
            atPath: manifestURL.path
        ) else {
            return []
        }
        do {
            let data = try Data(contentsOf: manifestURL)
            return try JSONDecoder().decode(
                [BackupEntry].self, from: data
            )
        } catch {
            logger.warning("Manifest load failed: \(error.localizedDescription)")
            return []
        }
    }

    func saveManifest(_ entries: [BackupEntry]) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(entries)
            try data.write(to: manifestURL)
        } catch {
            logger.error("Manifest save failed: \(error.localizedDescription)")
        }
    }

    // MARK: Private

    // MARK: - Private Helpers

    private func ensureBackupDirectory() {
        if !FileManager.default.fileExists(
            atPath: localBackupDir.path
        ) {
            try? FileManager.default.createDirectory(
                at: localBackupDir,
                withIntermediateDirectories: true
            )
        }
    }

    private func checkpointWAL(storeURL: URL) throws {
        var db: OpaquePointer?
        let rc = sqlite3_open_v2(
            storeURL.path, &db, SQLITE_OPEN_READWRITE, nil
        )
        defer { sqlite3_close(db) }
        guard rc == SQLITE_OK else {
            throw BackupError.checkpointFailed(rc)
        }
        let wal = sqlite3_wal_checkpoint_v2(
            db, nil, SQLITE_CHECKPOINT_TRUNCATE, nil, nil
        )
        guard wal == SQLITE_OK else {
            throw BackupError.checkpointFailed(wal)
        }
    }

    private func createSnapshotFile(
        trigger: BackupTrigger,
        storeURL: URL
    ) throws -> BackupEntry {
        let timestamp = Date()
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd_HHmmss"
        let filename =
            "carrierwave_\(fmt.string(from: timestamp)).sqlite"
        let destURL = localBackupDir
            .appendingPathComponent(filename)

        try FileManager.default.copyItem(
            at: storeURL, to: destURL
        )

        let attrs = try FileManager.default.attributesOfItem(
            atPath: destURL.path
        )
        let size = (attrs[.size] as? Int64) ?? 0
        let qsoCount = countQSOs(in: destURL)
        let version = Bundle.main.infoDictionary?[
            "CFBundleShortVersionString"
        ] as? String ?? "unknown"

        return BackupEntry(
            id: UUID(), timestamp: timestamp,
            trigger: trigger, qsoCount: qsoCount,
            sizeBytes: size, appVersion: version,
            location: .local, filename: filename
        )
    }

    private func countQSOs(in dbURL: URL) -> Int {
        var db: OpaquePointer?
        guard sqlite3_open_v2(
            dbURL.path, &db, SQLITE_OPEN_READONLY, nil
        ) == SQLITE_OK else {
            sqlite3_close(db)
            return 0
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(
            db, "SELECT COUNT(*) FROM ZQSO",
            -1, &stmt, nil
        ) == SQLITE_OK,
            sqlite3_step(stmt) == SQLITE_ROW
        else {
            sqlite3_finalize(stmt)
            return 0
        }
        let count = Int(sqlite3_column_int64(stmt, 0))
        sqlite3_finalize(stmt)
        return count
    }

    // MARK: - Pruning

    private func pruneLocal() {
        var manifest = loadManifest()
        guard manifest.count > maxLocalBackups else {
            return
        }

        let sorted = manifest.sorted {
            $0.timestamp < $1.timestamp
        }

        var keepByTrigger: Set<UUID> = []
        for trigger in [
            BackupTrigger.launch, .preSync,
            .preImport, .manual, .preRestore,
        ] {
            if let newest = sorted.last(where: {
                $0.trigger == trigger
            }) {
                keepByTrigger.insert(newest.id)
            }
        }

        var toRemove: [BackupEntry] = []
        for entry in sorted {
            let remaining = manifest.count - toRemove.count
            if remaining <= maxLocalBackups {
                break
            }
            if !keepByTrigger.contains(entry.id) {
                toRemove.append(entry)
            }
        }

        for entry in toRemove {
            let url = localBackupDir
                .appendingPathComponent(entry.filename)
            try? FileManager.default.removeItem(at: url)
            manifest.removeAll { $0.id == entry.id }
            logger.info("Pruned: \(entry.filename)")
        }

        saveManifest(manifest)
    }
}

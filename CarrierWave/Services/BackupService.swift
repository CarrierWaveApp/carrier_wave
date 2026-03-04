import CarrierWaveData
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

    /// Count visible, non-metadata QSOs using SwiftData.
    /// Runs on a background ModelContext to avoid blocking the main thread.
    nonisolated static func visibleQSOCount(
        in container: ModelContainer
    ) -> Int {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<QSO>(
            predicate: #Predicate {
                !$0.isHidden
                    && $0.mode != "WEATHER"
                    && $0.mode != "SOLAR"
                    && $0.mode != "NOTE"
            }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    // MARK: - Snapshot

    /// Create a snapshot of the database.
    /// Pass `qsoCount` from the app's SwiftData context for an accurate count.
    @discardableResult
    func snapshot(
        trigger: BackupTrigger,
        storeURL: URL,
        qsoCount: Int = 0
    ) async -> BackupEntry? {
        do {
            ensureBackupDirectory()
            try checkpointWAL(storeURL: storeURL)

            let entry = try createSnapshotFile(
                trigger: trigger, storeURL: storeURL,
                qsoCount: qsoCount
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

    func calculateBundleSize(_ bundleURL: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: bundleURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(
                forKeys: [.fileSizeKey]
            )
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }

    // MARK: Private

    private static let metadataModes: Set<String> = [
        "WEATHER", "SOLAR", "NOTE",
    ]

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
        storeURL: URL,
        qsoCount: Int
    ) throws -> BackupEntry {
        let timestamp = Date()
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd_HHmmss"
        let filename =
            "carrierwave_\(fmt.string(from: timestamp)).cwbackup"
        let bundleURL = localBackupDir
            .appendingPathComponent(filename)

        let fm = FileManager.default
        try fm.createDirectory(
            at: bundleURL, withIntermediateDirectories: true
        )

        // Copy database into bundle
        let dbDest = bundleURL
            .appendingPathComponent("database.sqlite")
        try fm.copyItem(at: storeURL, to: dbDest)

        // Copy session photos into bundle
        copyPhotosIntoBundle(bundleURL)

        let size = calculateBundleSize(bundleURL)
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

    private func copyPhotosIntoBundle(_ bundleURL: URL) {
        let fm = FileManager.default
        let documentsDir = fm.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!
        let photosDir = documentsDir
            .appendingPathComponent("SessionPhotos")

        guard fm.fileExists(atPath: photosDir.path) else {
            return
        }

        let destPhotos = bundleURL
            .appendingPathComponent("SessionPhotos")
        do {
            try fm.copyItem(at: photosDir, to: destPhotos)
        } catch {
            logger.warning(
                "Photo backup failed: \(error.localizedDescription)"
            )
        }
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

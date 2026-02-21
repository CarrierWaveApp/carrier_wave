import Foundation
import os
import SQLite3

// MARK: - BackupService Restore & iCloud

extension BackupService {
    /// Validate a backup file's integrity
    func validateBackup(
        _ entry: BackupEntry
    ) -> Result<Void, BackupError> {
        let url = urlForEntry(entry)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .failure(.backupFileNotFound)
        }

        var db: OpaquePointer?
        let openResult = sqlite3_open_v2(
            url.path, &db, SQLITE_OPEN_READONLY, nil
        )
        defer { sqlite3_close(db) }

        guard openResult == SQLITE_OK else {
            return .failure(
                .integrityCheckFailed("Could not open database")
            )
        }

        var stmt: OpaquePointer?
        let sql = "PRAGMA integrity_check"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK
        else {
            return .failure(
                .integrityCheckFailed(
                    "Could not prepare integrity check"
                )
            )
        }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return .failure(
                .integrityCheckFailed(
                    "Integrity check returned no results"
                )
            )
        }

        let result = String(cString: sqlite3_column_text(stmt, 0))
        if result == "ok" {
            return .success(())
        } else {
            return .failure(.integrityCheckFailed(result))
        }
    }

    /// Stage a restore: create safety backup, validate, write marker
    func stageRestore(
        entry: BackupEntry,
        storeURL: URL
    ) async throws {
        if FileManager.default.fileExists(
            atPath: Self.pendingRestoreURL.path
        ) {
            throw BackupError.restoreInProgress
        }

        // Create pre-restore safety backup
        _ = await snapshot(trigger: .preRestore, storeURL: storeURL)

        // Validate the backup
        let validation = validateBackup(entry)
        if case let .failure(error) = validation {
            throw error
        }

        // If iCloud backup, copy to local first
        if entry.location == .icloud {
            try copyICloudBackupToLocal(entry: entry)
        }

        // Write pending restore marker
        let pending = PendingRestore(
            backupFilename: entry.filename,
            backupTimestamp: entry.timestamp,
            stagedAt: Date()
        )
        let data = try JSONEncoder().encode(pending)
        try data.write(to: Self.pendingRestoreURL)

        logger.info("Restore staged: \(entry.filename)")
    }

    /// Check if there is a pending restore to apply on launch
    nonisolated static func checkPendingRestore() -> PendingRestore? {
        guard FileManager.default.fileExists(
            atPath: pendingRestoreURL.path
        ) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: pendingRestoreURL)
            return try JSONDecoder().decode(
                PendingRestore.self, from: data
            )
        } catch {
            try? FileManager.default.removeItem(at: pendingRestoreURL)
            return nil
        }
    }

    /// Apply a pending restore by swapping the database file.
    /// Call BEFORE creating the ModelContainer.
    nonisolated static func applyPendingRestore(
        storeURL: URL
    ) -> PendingRestore? {
        guard let pending = checkPendingRestore() else {
            return nil
        }

        let library = FileManager.default.urls(
            for: .libraryDirectory, in: .userDomainMask
        ).first!
        let backupDir = library.appendingPathComponent("Backups")
        let backupURL = backupDir.appendingPathComponent(
            pending.backupFilename
        )

        guard FileManager.default.fileExists(atPath: backupURL.path)
        else {
            try? FileManager.default.removeItem(at: pendingRestoreURL)
            return nil
        }

        do {
            // Remove existing store files
            for ext in ["", ".wal", ".shm"] {
                let url = ext.isEmpty
                    ? storeURL
                    : storeURL.appendingPathExtension(
                        String(ext.dropFirst())
                    )
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
            }

            // Copy backup to store location
            try FileManager.default.copyItem(
                at: backupURL, to: storeURL
            )

            // Clear the marker
            try FileManager.default.removeItem(at: pendingRestoreURL)

            // Pause iCloud sync after restore
            UserDefaults.standard.set(
                false, forKey: "cloudSyncEnabled"
            )
            UserDefaults.standard.set(
                true, forKey: "restoredFromBackup"
            )

            return pending
        } catch {
            try? FileManager.default.removeItem(at: pendingRestoreURL)
            return nil
        }
    }

    /// Delete a specific backup
    func deleteBackup(_ entry: BackupEntry) {
        let url = urlForEntry(entry)
        try? FileManager.default.removeItem(at: url)

        var manifest = loadManifest()
        manifest.removeAll { $0.id == entry.id }
        saveManifest(manifest)
    }

    // MARK: - iCloud Drive Sync

    func syncToICloud() {
        guard let icloudDir = icloudBackupDir else {
            return
        }

        let fm = FileManager.default
        if !fm.fileExists(atPath: icloudDir.path) {
            try? fm.createDirectory(
                at: icloudDir,
                withIntermediateDirectories: true
            )
        }

        let manifest = loadManifest()
        let localEntries = manifest.filter { $0.location == .local }
        let newest = localEntries
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(maxICloudBackups)

        for entry in newest {
            let src = localBackupDir
                .appendingPathComponent(entry.filename)
            let dst = icloudDir
                .appendingPathComponent(entry.filename)
            guard fm.fileExists(atPath: src.path) else {
                continue
            }
            if fm.fileExists(atPath: dst.path) {
                continue
            }

            let coordinator = NSFileCoordinator()
            var error: NSError?
            coordinator.coordinate(
                writingItemAt: dst,
                options: .forReplacing,
                error: &error
            ) { coordURL in
                try? fm.copyItem(at: src, to: coordURL)
            }
        }

        pruneICloud(keeping: Set(newest.map(\.filename)))
    }

    // MARK: - Private iCloud Helpers

    private func copyICloudBackupToLocal(
        entry: BackupEntry
    ) throws {
        let sourceURL = icloudBackupDir?
            .appendingPathComponent(entry.filename)
        guard let sourceURL,
              FileManager.default.fileExists(atPath: sourceURL.path)
        else {
            throw BackupError.backupFileNotFound
        }
        let destURL = localBackupDir
            .appendingPathComponent(entry.filename)
        if !FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.copyItem(
                at: sourceURL, to: destURL
            )
        }
    }

    private func pruneICloud(keeping keepFilenames: Set<String>) {
        guard let icloudDir = icloudBackupDir else {
            return
        }
        let fm = FileManager.default

        guard let files = try? fm.contentsOfDirectory(
            at: icloudDir, includingPropertiesForKeys: nil
        ) else {
            return
        }

        for file in files where file.pathExtension == "sqlite" {
            if !keepFilenames.contains(file.lastPathComponent) {
                try? fm.removeItem(at: file)
                logger.info("Pruned iCloud backup: \(file.lastPathComponent)")
            }
        }
    }

    func loadICloudBackups() -> [BackupEntry] {
        guard let icloudDir = icloudBackupDir else {
            return []
        }
        let fm = FileManager.default

        guard let files = try? fm.contentsOfDirectory(
            at: icloudDir,
            includingPropertiesForKeys: [
                .fileSizeKey, .creationDateKey,
            ]
        ) else {
            return []
        }

        return files
            .filter { $0.pathExtension == "sqlite" }
            .compactMap { url -> BackupEntry? in
                let attrs = try? fm.attributesOfItem(
                    atPath: url.path
                )
                let size = (attrs?[.size] as? Int64) ?? 0
                let created = (attrs?[.creationDate] as? Date)
                    ?? Date()

                return BackupEntry(
                    id: UUID(),
                    timestamp: created,
                    trigger: .manual,
                    qsoCount: 0,
                    sizeBytes: size,
                    appVersion: "unknown",
                    location: .icloud,
                    filename: url.lastPathComponent
                )
            }
    }
}

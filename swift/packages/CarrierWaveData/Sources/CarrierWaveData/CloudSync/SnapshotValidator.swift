import Foundation
import OSLog
import SQLite3

/// Validates downloaded SQLite snapshots before they replace the
/// local database, and creates emergency backups before destructive
/// operations.
public enum SnapshotValidator {
    /// Open the SQLite file and verify it contains at least one QSO row.
    /// Returns false if the file can't be opened or the table is empty.
    public static func hasQSOs(at url: URL) -> Bool {
        var db: OpaquePointer?
        let rc = sqlite3_open_v2(
            url.path, &db, SQLITE_OPEN_READONLY, nil
        )
        defer { sqlite3_close(db) }
        guard rc == SQLITE_OK else {
            return false
        }

        var stmt: OpaquePointer?
        let sql = "SELECT COUNT(*) FROM ZQSO LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK
        else {
            return false
        }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return false
        }
        return sqlite3_column_int64(stmt, 0) > 0
    }

    /// Copy the current database to Library/EmergencyBackup before
    /// a snapshot restore replaces it.
    public static func backupBeforeRestore(
        storeURL: URL, logger: Logger
    ) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: storeURL.path) else {
            return
        }
        let library = fm.urls(
            for: .libraryDirectory, in: .userDomainMask
        ).first!
        let backupDir = library.appendingPathComponent(
            "EmergencyBackup"
        )
        try? fm.createDirectory(
            at: backupDir, withIntermediateDirectories: true
        )
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let destURL = backupDir.appendingPathComponent(
            "pre-sync-\(timestamp).sqlite"
        )
        do {
            try fm.copyItem(at: storeURL, to: destURL)
            let walURL = storeURL.appendingPathExtension("wal")
            if fm.fileExists(atPath: walURL.path) {
                try fm.copyItem(
                    at: walURL,
                    to: destURL.appendingPathExtension("wal")
                )
            }
            logger.info(
                "Pre-restore backup saved: \(destURL.lastPathComponent)"
            )
        } catch {
            logger.error(
                "Pre-restore backup failed: \(error.localizedDescription)"
            )
        }
    }
}

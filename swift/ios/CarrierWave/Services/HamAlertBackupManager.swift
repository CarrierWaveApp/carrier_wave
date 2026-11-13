// HamAlert Backup Manager
//
// Stores and retrieves HamAlert trigger backups as JSON files
// in the app's documents directory. Each backup captures the
// full trigger list from HamAlert before an export overwrites them.

import Foundation

// MARK: - HamAlertBackupManager

nonisolated enum HamAlertBackupManager {
    // MARK: Internal

    static func save(_ triggers: [[String: Any]]) throws -> HamAlertBackupEntry {
        try FileManager.default.createDirectory(
            at: backupsDirectory,
            withIntermediateDirectories: true
        )

        let now = Date()
        let filename = filenameFormatter.string(from: now) + ".json"
        let fileURL = backupsDirectory.appendingPathComponent(filename)

        let data = try JSONSerialization.data(
            withJSONObject: triggers, options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: fileURL)

        return HamAlertBackupEntry(
            date: now,
            triggerCount: triggers.count,
            filename: filename
        )
    }

    static func listBackups() -> [HamAlertBackupEntry] {
        guard let contents = try? FileManager.default
            .contentsOfDirectory(
                at: backupsDirectory,
                includingPropertiesForKeys: [.creationDateKey]
            )
        else {
            return []
        }

        return contents
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> HamAlertBackupEntry? in
                guard let data = try? Data(contentsOf: url),
                      let triggers = try? JSONSerialization.jsonObject(
                          with: data
                      ) as? [[String: Any]]
                else {
                    return nil
                }

                let stem = url.deletingPathExtension().lastPathComponent
                let date = filenameFormatter.date(from: stem) ?? Date()

                return HamAlertBackupEntry(
                    date: date,
                    triggerCount: triggers.count,
                    filename: url.lastPathComponent
                )
            }
            .sorted { $0.date > $1.date }
    }

    static func loadTriggers(
        from entry: HamAlertBackupEntry
    ) throws -> [[String: Any]] {
        let fileURL = backupsDirectory
            .appendingPathComponent(entry.filename)
        let data = try Data(contentsOf: fileURL)
        guard let triggers = try JSONSerialization.jsonObject(
            with: data
        ) as? [[String: Any]] else {
            throw HamAlertError.restoreFailed
        }
        return triggers
    }

    static func deleteBackup(_ entry: HamAlertBackupEntry) {
        let fileURL = backupsDirectory
            .appendingPathComponent(entry.filename)
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: Private

    private static let filenameFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd_HHmmss"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt
    }()

    private static var backupsDirectory: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HamAlertBackups", isDirectory: true)
    }
}

// MARK: - HamAlertBackupEntry

nonisolated struct HamAlertBackupEntry: Identifiable {
    let date: Date
    let triggerCount: Int
    let filename: String

    var id: String {
        filename
    }
}

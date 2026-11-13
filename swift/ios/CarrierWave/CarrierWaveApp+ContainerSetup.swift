import CarrierWaveData
import OSLog
import SwiftData
import SwiftUI

// MARK: - ContainerInitFailureRecord

/// Persisted record of a `ModelContainer.init` failure that triggered a
/// silent store wipe. Written to `Library/ContainerInitFailure.json`
/// before the wipe runs so the next launch — and any future diagnostic
/// bundle — can surface what actually happened. The previous-process
/// `os_log` fault was unrecoverable; this file is the replacement.
struct ContainerInitFailureRecord: Codable {
    let timestamp: Date
    let errorDescription: String
    let errorTypeName: String
    let appVersion: String
    let buildNumber: String
    let storeSizeBytes: Int64?
    let walSizeBytes: Int64?
    let shmSizeBytes: Int64?
    let emergencyBackupFilename: String?
}

// MARK: - ContainerSetup

/// Standalone helper for ModelContainer creation and emergency recovery.
/// These are free-standing static methods rather than an extension on
/// CarrierWaveApp to work around a MemberImportVisibility + wholemodule
/// compiler issue where Foundation types become invisible in extensions
/// of SwiftUI App types in archive builds.
enum ContainerSetup {
    // MARK: Internal

    /// Remove duplicate EquipmentItems, keeping the first by catalogName.
    @MainActor
    static func deduplicateEquipment(
        container: ModelContainer
    ) {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<EquipmentItem>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        descriptor.fetchLimit = 500
        guard let items = try? context.fetch(descriptor) else {
            return
        }

        var seen = Set<String>()
        for item in items {
            let key = "\(item.categoryRawValue):\(item.catalogName.lowercased())"
            if seen.contains(key) {
                context.delete(item)
            } else {
                seen.insert(key)
            }
        }

        try? context.save()
    }

    /// Build a `ModelContainer` from the user's on-disk store, or fall
    /// back to an empty in-memory container with the broken store
    /// preserved on disk if init fails. The broken-init case writes a
    /// `ContainerInitFailureRecord` so `CarrierWaveApp` can route the
    /// user into `RecoveryModeView` instead of the normal app surface.
    /// Importantly, it does NOT delete the original store — that is
    /// only done if the user explicitly confirms via `confirmedReset`.
    static func createModelContainer(
        schema: Schema, configuration: ModelConfiguration
    ) -> ModelContainer {
        do {
            return try ModelContainer(
                for: schema, configurations: [configuration]
            )
        } catch {
            let storeURL = configuration.url
            let logger = Logger(
                subsystem: "com.carrierwave",
                category: "ModelContainer"
            )
            logger.fault(
                "ModelContainer init failed, will enter recovery mode: \(error.localizedDescription)"
            )

            // Copy the broken store to Library/EmergencyBackup so it
            // survives even if the user later confirms a reset.
            let backupFilename = emergencyBackup(
                storeURL: storeURL, logger: logger
            )

            // Persist the structured failure record. This is the
            // signal `CarrierWaveApp` reads to switch to recovery mode.
            writeFailureRecord(
                error: error,
                storeURL: storeURL,
                emergencyBackupFilename: backupFilename
            )

            // In-memory fallback container so SwiftUI can construct a
            // tree. The user never sees `ContentView` while a failure
            // record is pending; `RecoveryModeView` covers the screen.
            return makeInMemoryFallback(schema: schema)
        }
    }

    /// Apply the destructive reset that the old (pre-recovery-mode)
    /// `createModelContainer` did automatically. Only call from a
    /// user-confirmed action in `RecoveryModeView`. After this returns
    /// the failure record is cleared and the user must relaunch.
    static func confirmedReset(storeURL: URL) {
        try? FileManager.default.removeItem(at: storeURL)
        try? FileManager.default.removeItem(
            at: storeURL.appendingPathExtension("wal")
        )
        try? FileManager.default.removeItem(
            at: storeURL.appendingPathExtension("shm")
        )
        clearFailureRecord()
    }

    /// Copy the existing database to Library/EmergencyBackup before
    /// a destructive reset so the user can recover via support.
    /// Returns the saved filename on success so callers can record it
    /// in the failure log.
    @discardableResult
    static func emergencyBackup(
        storeURL: URL, logger: Logger
    ) -> String? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: storeURL.path) else {
            return nil
        }
        let backupDir = emergencyBackupDirectory()
        try? fileManager.createDirectory(
            at: backupDir, withIntermediateDirectories: true
        )
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let destURL = backupDir.appendingPathComponent(
            "database-\(timestamp).sqlite"
        )
        do {
            try fileManager.copyItem(at: storeURL, to: destURL)
            // Also copy WAL if present — it may contain unflushed data
            let walURL = storeURL.appendingPathExtension("wal")
            if fileManager.fileExists(atPath: walURL.path) {
                try fileManager.copyItem(
                    at: walURL,
                    to: destURL.appendingPathExtension("wal")
                )
            }
            logger.info(
                "Emergency backup saved: \(destURL.lastPathComponent)"
            )
            return destURL.lastPathComponent
        } catch {
            logger.error(
                "Emergency backup failed: \(error.localizedDescription)"
            )
            return nil
        }
    }

    /// Directory holding emergency backups of broken stores.
    /// Public for diagnostics + recovery surfacing.
    /// `nonisolated` so the `DiagnosticsCollector` actor can call it.
    nonisolated static func emergencyBackupDirectory() -> URL {
        let library = FileManager.default.urls(
            for: .libraryDirectory, in: .userDomainMask
        ).first!
        return library.appendingPathComponent("EmergencyBackup")
    }

    /// On-disk location of the persisted init-failure record.
    /// `nonisolated` so the `DiagnosticsCollector` actor can call it.
    nonisolated static func failureRecordURL() -> URL {
        let library = FileManager.default.urls(
            for: .libraryDirectory, in: .userDomainMask
        ).first!
        return library.appendingPathComponent("ContainerInitFailure.json")
    }

    /// Read any pending failure record. Returns nil if none on disk
    /// or the record is unreadable.
    static func loadPendingFailureRecord() -> ContainerInitFailureRecord? {
        let url = failureRecordURL()
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url)
        else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(
            ContainerInitFailureRecord.self, from: data
        )
    }

    /// Delete the failure record. Call after the user acknowledges
    /// the recovery alert so the next launch is silent.
    static func clearFailureRecord() {
        try? FileManager.default.removeItem(at: failureRecordURL())
    }

    // MARK: Private

    private static func makeInMemoryFallback(
        schema: Schema
    ) -> ModelContainer {
        let inMemory = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(
                for: schema, configurations: [inMemory]
            )
        } catch {
            fatalError(
                "Could not create in-memory recovery container: \(error)"
            )
        }
    }

    // MARK: - Failure record persistence

    private static func writeFailureRecord(
        error: Error,
        storeURL: URL,
        emergencyBackupFilename: String?
    ) {
        let bundle = Bundle.main
        let appVersion = bundle.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "?"
        let buildNumber = bundle.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "?"

        let record = ContainerInitFailureRecord(
            timestamp: Date(),
            errorDescription: error.localizedDescription,
            errorTypeName: String(reflecting: type(of: error)),
            appVersion: appVersion,
            buildNumber: buildNumber,
            storeSizeBytes: fileSize(at: storeURL),
            walSizeBytes: fileSize(
                at: storeURL.appendingPathExtension("wal")
            ),
            shmSizeBytes: fileSize(
                at: storeURL.appendingPathExtension("shm")
            ),
            emergencyBackupFilename: emergencyBackupFilename
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(record) else {
            return
        }
        try? data.write(to: failureRecordURL(), options: .atomic)
    }

    private static func fileSize(at url: URL) -> Int64? {
        let attrs = try? FileManager.default
            .attributesOfItem(atPath: url.path)
        return attrs?[.size] as? Int64
    }
}

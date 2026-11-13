import CarrierWaveData
import Foundation
import OSLog
import SwiftData
import UIKit
import ZIPFoundation

// MARK: - File Artifact Collectors

extension DiagnosticsCollector {
    func collectFileArtifacts() async -> [ArtifactResult] {
        // Pre-enumerate emergency-backup files on the calling actor
        // so the per-file tasks below stay simple and parallel.
        let emergencyBackupURLs = enumerateEmergencyBackupFiles()

        return await withTaskGroup(of: ArtifactResult.self) { group in
            group.addTask { await self.collectSyncDebugLog() }
            group.addTask { await self.collectCloudSyncEvents() }
            group.addTask { await self.collectBackupManifest() }
            group.addTask { await self.collectContainerInitFailure() }
            group.addTask { await self.collectStartupProfile() }
            group.addTask { await self.collectStorageInfo() }
            group.addTask { await self.collectLedgerTail() }
            group.addTask { await self.collectPerfSummary() }

            for url in emergencyBackupURLs {
                group.addTask {
                    await self.collectEmergencyBackupFile(url: url)
                }
            }

            var results: [ArtifactResult] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
    }

    func collectFile(
        label: String,
        filename: String,
        url: URL,
        optional: Bool = false
    ) -> ArtifactResult {
        let start = DispatchTime.now()
        guard FileManager.default.fileExists(atPath: url.path) else {
            if optional {
                return .skipped
            }
            return .failed(label: label, reason: "File not found")
        }
        do {
            let data = try Data(contentsOf: url)
            let elapsedMs = millisSince(start)
            return .success(DiagnosticArtifact(
                filename: filename, data: data, collectionMs: elapsedMs
            ))
        } catch {
            return .failed(
                label: label, reason: error.localizedDescription
            )
        }
    }

    // MARK: - Individual File Collectors

    private func collectSyncDebugLog() async -> ArtifactResult {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        return collectFile(
            label: "sync-debug-log",
            filename: "sync-debug-log.json",
            url: appSupport.appendingPathComponent(
                "sync-debug-log.json"
            )
        )
    }

    private func collectCloudSyncEvents() async -> ArtifactResult {
        let appSupport = FileManager.default.urls(
            for: .libraryDirectory, in: .userDomainMask
        ).first!
        return collectFile(
            label: "cloud-sync-events",
            filename: "cloud-sync-events.json",
            url: appSupport.appendingPathComponent("CloudSync")
                .appendingPathComponent("sync_events.json"),
            optional: true
        )
    }

    private func collectBackupManifest() async -> ArtifactResult {
        let library = FileManager.default.urls(
            for: .libraryDirectory, in: .userDomainMask
        ).first!
        return collectFile(
            label: "backup-manifest",
            filename: "backup-manifest.json",
            url: library.appendingPathComponent("Backups")
                .appendingPathComponent("backups.json")
        )
    }

    /// Persisted record from the last `ModelContainer.init` failure.
    /// Optional — only present after a silent recovery from a broken store.
    private func collectContainerInitFailure() async -> ArtifactResult {
        collectFile(
            label: "container-init-failure",
            filename: "container-init-failure.json",
            url: ContainerSetup.failureRecordURL(),
            optional: true
        )
    }

    /// All `Library/EmergencyBackup/database-*.sqlite[-wal|-shm]` files.
    /// Returned as URLs so the parent task group can collect each in
    /// parallel and so we don't hide the per-file count from the manifest.
    private func enumerateEmergencyBackupFiles() -> [URL] {
        let dir = ContainerSetup.emergencyBackupDirectory()
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else {
            return []
        }
        let allowed: Set = ["sqlite", "wal", "shm"]
        return urls
            .filter { allowed.contains($0.pathExtension) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Read one emergency-backup file into the bundle. Filename is
    /// prefixed `emergency-backup/` so the recipient can spot the
    /// grouping in the zip without us building a sub-archive.
    private func collectEmergencyBackupFile(
        url: URL
    ) async -> ArtifactResult {
        let labeled = "emergency-backup/\(url.lastPathComponent)"
        return collectFile(
            label: labeled,
            filename: labeled,
            url: url,
            optional: true
        )
    }

    private func collectStartupProfile() async -> ArtifactResult {
        let caches = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask
        ).first!
        return collectFile(
            label: "startup-profile",
            filename: "startup-profile.json",
            url: caches.appendingPathComponent(
                "startup-profile.json"
            ),
            optional: true
        )
    }

    func collectStorageInfo() async -> ArtifactResult {
        let start = DispatchTime.now()
        do {
            let info = try gatherStorageMetrics()
            let jsonData = try JSONSerialization.data(
                withJSONObject: info,
                options: [.prettyPrinted, .sortedKeys]
            )
            let elapsedMs = millisSince(start)
            return .success(DiagnosticArtifact(
                filename: "storage-info.json",
                data: jsonData,
                collectionMs: elapsedMs
            ))
        } catch {
            return .failed(
                label: "storage-info",
                reason: error.localizedDescription
            )
        }
    }

    private func gatherStorageMetrics() throws -> [String: Any] {
        var info: [String: Any] = [:]

        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let defaultStore = appSupport
            .appendingPathComponent("default.store")
        if let attrs = try? FileManager.default
            .attributesOfItem(atPath: defaultStore.path)
        {
            info["databaseSizeBytes"] =
                attrs[.size] as? Int64 ?? 0
        }

        let ledgerFiles = QSOLedger.allFiles()
        info["ledgerFiles"] = ledgerFiles.map {
            [
                "name": $0.url.lastPathComponent,
                "sizeBytes": $0.sizeBytes,
            ]
        }
        info["ledgerTotalBytes"] = ledgerFiles.reduce(
            into: Int64(0)
        ) { $0 += $1.sizeBytes }

        let documentsURL = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!
        let resourceValues = try documentsURL.resourceValues(
            forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
            ]
        )
        info["availableDiskBytes"] = resourceValues
            .volumeAvailableCapacityForImportantUsage
        info["physicalMemoryBytes"] = ProcessInfo.processInfo
            .physicalMemory

        return info
    }

    func collectPerfSummary() async -> ArtifactResult {
        let start = DispatchTime.now()
        let osVersion = await MainActor.run {
            UIDevice.current.systemVersion
        }
        let summary: [String: Any] = [
            "collectedAt": ISO8601DateFormatter()
                .string(from: Date()),
            "deviceModel": deviceModelIdentifier(),
            "osVersion": osVersion,
            "physicalMemoryMB": ProcessInfo.processInfo
                .physicalMemory / (1_024 * 1_024),
            "processorCount": ProcessInfo.processInfo
                .processorCount,
            "thermalState": thermalStateString(),
            "isLowPowerMode": ProcessInfo.processInfo
                .isLowPowerModeEnabled,
        ]
        do {
            let data = try JSONSerialization.data(
                withJSONObject: summary,
                options: [.prettyPrinted, .sortedKeys]
            )
            let elapsedMs = millisSince(start)
            return .success(DiagnosticArtifact(
                filename: "perf-summary.json",
                data: data,
                collectionMs: elapsedMs
            ))
        } catch {
            return .failed(
                label: "perf-summary",
                reason: error.localizedDescription
            )
        }
    }

    func collectLedgerTail() async -> ArtifactResult {
        let start = DispatchTime.now()
        let adiFiles = QSOLedger.allFiles().filter {
            $0.url.pathExtension == "adi"
        }
        let recentFiles = Array(adiFiles.prefix(2))

        guard !recentFiles.isEmpty else {
            return .failed(
                label: "ledger-tail",
                reason: "No ledger files found"
            )
        }

        var combined = Data()
        for file in recentFiles {
            guard file.sizeBytes <= 2 * 1_024 * 1_024 else {
                continue
            }
            if let fileData = try? Data(contentsOf: file.url) {
                let header = Data(
                    "--- \(file.url.lastPathComponent) ---\n"
                        .utf8
                )
                combined.append(header)
                combined.append(fileData)
                combined.append(Data("\n".utf8))
            }
        }

        guard !combined.isEmpty else {
            return .failed(
                label: "ledger-tail",
                reason: "All ledger files too large (>2 MB)"
            )
        }

        let elapsedMs = millisSince(start)
        return .success(DiagnosticArtifact(
            filename: "ledger-tail.adi",
            data: combined,
            collectionMs: elapsedMs
        ))
    }
}

// MARK: - Data Artifact Collectors

extension DiagnosticsCollector {
    func collectDataArtifacts(
        container: ModelContainer,
        includeDatabase: Bool
    ) async -> [ArtifactResult] {
        var results: [ArtifactResult] = []
        await results.append(
            collectRecentQSOs(container: container)
        )
        if includeDatabase {
            await results.append(
                collectDatabaseSnapshot(
                    container: container
                )
            )
        }
        return results
    }

    private func collectRecentQSOs(
        container: ModelContainer
    ) async -> ArtifactResult {
        let start = DispatchTime.now()
        do {
            let context = ModelContext(container)
            context.autosaveEnabled = false

            var descriptor = FetchDescriptor<QSO>(
                predicate: #Predicate { !$0.isHidden },
                sortBy: [SortDescriptor(
                    \.timestamp, order: .reverse
                )]
            )
            descriptor.fetchLimit = 50

            let qsos = try context.fetch(descriptor)
            let formatter = ISO8601DateFormatter()
            let snapshots = qsos.map { qso in
                RedactedQSOSnapshot(
                    id: qso.id.uuidString,
                    callsign: qso.callsign,
                    timestamp: formatter
                        .string(from: qso.timestamp),
                    band: qso.band,
                    mode: qso.mode,
                    frequency: qso.frequency,
                    rstSent: qso.rstSent,
                    rstReceived: qso.rstReceived,
                    myCallsign: qso.myCallsign,
                    myGrid: truncateGrid(qso.myGrid),
                    theirGrid: truncateGrid(qso.theirGrid),
                    parkReference: qso.parkReference,
                    importSource: qso.importSource.rawValue,
                    isHidden: qso.isHidden
                )
            }

            let data = try JSONEncoder.iso8601.encode(snapshots)
            let elapsedMs = millisSince(start)
            return .success(DiagnosticArtifact(
                filename: "recent-qsos.json",
                data: data,
                collectionMs: elapsedMs
            ))
        } catch {
            return .failed(
                label: "recent-qsos",
                reason: error.localizedDescription
            )
        }
    }

    private func collectDatabaseSnapshot(
        container: ModelContainer
    ) async -> ArtifactResult {
        let start = DispatchTime.now()
        do {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            var countDescriptor = FetchDescriptor<QSO>()
            countDescriptor.fetchLimit = 50_000
            let count = try context.fetchCount(countDescriptor)

            guard count < 50_000 else {
                return .failed(
                    label: "database-snapshot",
                    reason: "Skipped: \(count) QSOs exceeds "
                        + "50K limit"
                )
            }

            guard let storeURL = container.configurations
                .first?.url
            else {
                return .failed(
                    label: "database-snapshot",
                    reason: "Could not determine store URL"
                )
            }

            let data = try Data(contentsOf: storeURL)
            let elapsedMs = millisSince(start)
            return .success(DiagnosticArtifact(
                filename: "database.sqlite",
                data: data,
                collectionMs: elapsedMs
            ))
        } catch {
            return .failed(
                label: "database-snapshot",
                reason: error.localizedDescription
            )
        }
    }
}

// MARK: - OS Log Collector

extension DiagnosticsCollector {
    func collectOSLog() async -> ArtifactResult {
        await Task.detached(priority: .utility) {
            let start = DispatchTime.now()
            do {
                let store = try OSLogStore(
                    scope: .currentProcessIdentifier
                )
                let oneHourAgo = store.position(
                    date: Date().addingTimeInterval(-3_600)
                )
                let entries = try store.getEntries(
                    at: oneHourAgo
                )

                var lines: [String] = []
                for entry in entries.prefix(2_000) {
                    lines.append(
                        "[\(entry.date)] "
                            + "\(entry.composedMessage)"
                    )
                }

                let text = lines.joined(separator: "\n")
                let data = text.data(using: .utf8) ?? Data()
                let elapsed = DispatchTime.now()
                    .uptimeNanoseconds
                    - start.uptimeNanoseconds
                let elapsedMs = Int(elapsed / 1_000_000)
                return ArtifactResult.success(
                    DiagnosticArtifact(
                        filename: "os-log.txt",
                        data: data,
                        collectionMs: elapsedMs
                    )
                )
            } catch {
                return ArtifactResult.failed(
                    label: "os-log",
                    reason: error.localizedDescription
                )
            }
        }.value
    }
}

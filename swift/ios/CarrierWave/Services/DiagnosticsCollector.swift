import CarrierWaveData
import Foundation
import SwiftData
import UIKit
import ZIPFoundation

// MARK: - DiagnosticsCollector

/// Collects diagnostic data from all app systems and packages
/// it into a zip file. Each collector is isolated — if one fails,
/// the rest continue.
actor DiagnosticsCollector {
    // MARK: Internal

    enum CollectionStatus {
        case collectingLogs
        case packagingSyncHistory
        case checkingStorage
        case creatingPackage
        case done
    }

    struct CollectionOptions {
        var userDescription: String?
        var includeDatabase: Bool = false
    }

    struct CollectionResult {
        let zipURL: URL
        let sizeBytes: Int64
        let failures: [String]
    }

    struct DiagnosticArtifact {
        let filename: String
        let data: Data
        let collectionMs: Int
    }

    enum ArtifactResult {
        case success(DiagnosticArtifact)
        case failed(label: String, reason: String)
        case skipped
    }

    // MARK: - Snapshot Types

    struct MainActorSnapshot {
        let deviceInfo: DeviceInfoSnapshot
        let serviceStatus: ServiceStatusSnapshot
        let callsignInfo: CallsignInfoSnapshot
        let syncState: SyncStateSnapshot
        let uploadDiagnostics: Data?
    }

    struct DeviceInfoSnapshot: Codable {
        let appVersion: String
        let buildNumber: String
        let iosVersion: String
        let deviceModel: String
        let debugMode: Bool
    }

    struct ServiceStatusSnapshot: Codable {
        let qrzConfigured: Bool
        let potaConfigured: Bool
        let lofiConfigured: Bool
        let lofiLinked: Bool
        let lofiCallsign: String?
        let lofiLastSyncMillis: Int64
        let lotwConfigured: Bool
        let hamrsConfigured: Bool
        let iCloudStatus: String
    }

    struct CallsignInfoSnapshot: Codable {
        let currentCallsign: String?
        let previousCallsigns: [String]
    }

    struct SyncStateSnapshot: Codable {
        let isEnabled: Bool
        let syncStatus: String
        let pendingCount: Int
        let lastSyncDate: Date?
        let errorMessage: String?
        let uploadGoal: Int?
        let uploadedCount: Int
    }

    enum DiagnosticsError: Error {
        case zipCreationFailed
    }

    func collect(
        options: CollectionOptions,
        container: ModelContainer,
        statusCallback: @Sendable (CollectionStatus) -> Void
    ) async throws -> CollectionResult {
        let startTime = Date()
        let reportId = UUID()
        var artifacts: [DiagnosticArtifact] = []
        var failures: [String] = []

        statusCallback(.collectingLogs)
        let snapshot = await collectMainActorSnapshot()

        statusCallback(.packagingSyncHistory)
        let fileResults = await collectFileArtifacts()
        appendResults(fileResults, to: &artifacts, failures: &failures)

        statusCallback(.checkingStorage)
        let dataResults = await collectDataArtifacts(
            container: container,
            includeDatabase: options.includeDatabase
        )
        appendResults(dataResults, to: &artifacts, failures: &failures)

        let osLogResult = await collectOSLog()
        appendResults([osLogResult], to: &artifacts, failures: &failures)

        artifacts.append(
            contentsOf: buildSnapshotArtifacts(from: snapshot)
        )

        statusCallback(.creatingPackage)
        let duration = Date().timeIntervalSince(startTime)
        let manifest = buildManifest(ManifestInput(
            reportId: reportId,
            snapshot: snapshot,
            options: options,
            artifacts: artifacts,
            failures: failures,
            durationSeconds: duration
        ))
        artifacts.append(manifest)

        let zipURL = try assembleZip(
            artifacts: artifacts, timestamp: startTime
        )
        let fileSize = (try? FileManager.default.attributesOfItem(
            atPath: zipURL.path
        )[.size] as? Int64) ?? 0

        statusCallback(.done)

        return CollectionResult(
            zipURL: zipURL, sizeBytes: fileSize, failures: failures
        )
    }

    // MARK: - MainActor Snapshot

    @MainActor
    func collectMainActorSnapshot() -> MainActorSnapshot {
        let bugService = BugReportService()
        let debugMode = UserDefaults.standard.bool(
            forKey: "debugMode"
        )
        let deviceInfo = bugService.collectDeviceInfo(
            debugMode: debugMode
        )
        let serviceStatus = bugService.collectServiceStatus()
        let callsignInfo = bugService.collectCallsignInfo()

        let sync = CloudSyncService.shared
        let syncState = SyncStateSnapshot(
            isEnabled: sync.isEnabled,
            syncStatus: sync.syncStatus.displayText,
            pendingCount: sync.counts.totalDirty,
            lastSyncDate: sync.lastSyncDate,
            errorMessage: sync.errorMessage,
            uploadGoal: sync.uploadGoal,
            uploadedCount: sync.uploadedCount
        )

        let diagnosticsData = try? JSONEncoder.iso8601
            .encode(UploadDiagnosticStore.shared.diagnostics)

        return MainActorSnapshot(
            deviceInfo: DeviceInfoSnapshot(
                appVersion: deviceInfo.appVersion,
                buildNumber: deviceInfo.buildNumber,
                iosVersion: deviceInfo.iosVersion,
                deviceModel: deviceInfo.deviceModel,
                debugMode: deviceInfo.debugMode
            ),
            serviceStatus: ServiceStatusSnapshot(
                qrzConfigured: serviceStatus.qrzConfigured,
                potaConfigured: serviceStatus.potaConfigured,
                lofiConfigured: serviceStatus.lofiConfigured,
                lofiLinked: serviceStatus.lofiLinked,
                lofiCallsign: serviceStatus.lofiCallsign,
                lofiLastSyncMillis: serviceStatus
                    .lofiLastSyncMillis,
                lotwConfigured: serviceStatus.lotwConfigured,
                hamrsConfigured: serviceStatus.hamrsConfigured,
                iCloudStatus: serviceStatus.iCloudStatus
            ),
            callsignInfo: CallsignInfoSnapshot(
                currentCallsign: callsignInfo.currentCallsign,
                previousCallsigns: callsignInfo.previousCallsigns
            ),
            syncState: syncState,
            uploadDiagnostics: diagnosticsData
        )
    }

    // MARK: - Helpers

    func millisSince(_ start: DispatchTime) -> Int {
        let elapsed = DispatchTime.now().uptimeNanoseconds
            - start.uptimeNanoseconds
        return Int(elapsed / 1_000_000)
    }

    func truncateGrid(_ grid: String?) -> String? {
        guard let grid, grid.count > 4 else {
            return grid
        }
        return String(grid.prefix(4))
    }

    func deviceModelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingCString: $0) ?? "Unknown"
            }
        }
    }

    func thermalStateString() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }

    // MARK: Private

    private func appendResults(
        _ results: [ArtifactResult],
        to artifacts: inout [DiagnosticArtifact],
        failures: inout [String]
    ) {
        for result in results {
            switch result {
            case let .success(artifact):
                artifacts.append(artifact)
            case let .failed(label, reason):
                failures.append("\(label): \(reason)")
            case .skipped:
                break
            }
        }
    }
}

// MARK: - RedactedQSOSnapshot

struct RedactedQSOSnapshot: Codable {
    let id: String
    let callsign: String
    let timestamp: String
    let band: String?
    let mode: String?
    let frequency: Double?
    let rstSent: String?
    let rstReceived: String?
    let myCallsign: String?
    let myGrid: String?
    let theirGrid: String?
    let parkReference: String?
    let importSource: String
    let isHidden: Bool
}

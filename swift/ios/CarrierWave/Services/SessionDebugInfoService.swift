import CarrierWaveCore
import CarrierWaveData
import Foundation
import SwiftData
import UIKit

// MARK: - SessionDebugReport

/// Bundle of debug artifacts for a single session. Suitable for attaching to
/// a support request — includes the database subset, generated ADIF, sync
/// debug logs, and environment info.
struct SessionDebugReport {
    let summary: String
    let adif: String
    let filenameStem: String

    /// Single-file report combining summary text and ADIF content, suitable for
    /// sharing as a `.txt` file or pasting into a chat.
    var combinedText: String {
        """
        \(summary)

        ================================================================
        ADIF EXPORT
        ================================================================
        \(adif)
        """
    }
}

// MARK: - SessionDebugInfoService

/// Gathers every piece of state relevant to debugging a "something is wrong
/// with this session" complaint and formats it into a shareable report.
@MainActor
enum SessionDebugInfoService {
    // MARK: Internal

    /// Build a debug report for the given session.
    /// Must be called from the main actor — reads SwiftData models and
    /// `SyncDebugLog.shared`.
    static func buildReport(
        session: LoggingSession,
        qsos: [QSO],
        activationMetadata: ActivationMetadata?,
        modelContext: ModelContext
    ) async -> SessionDebugReport {
        let spots = fetchSpots(sessionId: session.id, context: modelContext)

        let snapshots = qsos.map { QSOExportSnapshot(from: $0) }
        let qsoServiceRows = qsos.map { qso in
            QSOServiceRow(
                id: qso.id,
                callsign: qso.callsign,
                timestamp: qso.timestamp,
                presence: qso.servicePresence.map { ServicePresenceRow(from: $0) }
            )
        }

        let logs = collectRelevantLogs(session: session)
        let deviceInfo = collectDeviceInfo()
        let callsignInfo = collectCallsignInfo()

        let summary = Formatter.format(
            session: session,
            qsos: qsos,
            qsoServiceRows: qsoServiceRows,
            spots: spots,
            metadata: activationMetadata,
            logs: logs,
            deviceInfo: deviceInfo,
            callsignInfo: callsignInfo
        )

        let adif = await generateADIF(session: session, snapshots: snapshots)
        let filenameStem = Formatter.filenameStem(session: session)

        return SessionDebugReport(summary: summary, adif: adif, filenameStem: filenameStem)
    }

    // MARK: Private

    // MARK: - Collection helpers

    private static func fetchSpots(sessionId: UUID, context: ModelContext) -> [SessionSpot] {
        let predicate = #Predicate<SessionSpot> { spot in
            spot.loggingSessionId == sessionId
        }
        var descriptor = FetchDescriptor<SessionSpot>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        descriptor.fetchLimit = 500
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Return log entries whose timestamp falls within the session's window
    /// (plus a padding on either side), plus any of the most recent entries as
    /// a fallback when no entries overlap the window.
    private static func collectRelevantLogs(
        session: LoggingSession
    ) -> [SyncDebugLog.LogEntry] {
        let padding: TimeInterval = 60 * 60 // 1 hour
        let start = session.startedAt.addingTimeInterval(-padding)
        let end = (session.endedAt ?? Date()).addingTimeInterval(padding)
        let all = SyncDebugLog.shared.logEntries
        let inWindow = all.filter { $0.timestamp >= start && $0.timestamp <= end }
        if !inWindow.isEmpty {
            return Array(inWindow.prefix(200))
        }
        return Array(all.prefix(50))
    }

    private static func collectDeviceInfo() -> DeviceInfoSnapshot {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return DeviceInfoSnapshot(
            appVersion: version,
            buildNumber: build,
            iosVersion: UIDevice.current.systemVersion,
            deviceModel: rawDeviceModel(),
            locale: Locale.current.identifier,
            timeZone: TimeZone.current.identifier
        )
    }

    private static func collectCallsignInfo() -> (current: String?, previous: [String]) {
        let current = CallsignAliasService.shared.getCurrentCallsign()
        let previous = CallsignAliasService.shared.getPreviousCallsigns()
        return (current, previous)
    }

    private static func rawDeviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingCString: $0) ?? "Unknown"
            }
        }
    }

    // MARK: - ADIF

    private static func generateADIF(
        session: LoggingSession,
        snapshots: [QSOExportSnapshot]
    ) async -> String {
        let exporter = ADIFExportService()
        let parkRef = session.parkReference ?? ""
        let callsign = session.stationCallsign ?? session.myCallsign
        return await exporter.generateADIF(
            for: snapshots,
            parkReference: parkRef,
            parkName: nil,
            activatorCallsign: callsign
        )
    }
}

// MARK: - DeviceInfoSnapshot

struct DeviceInfoSnapshot {
    let appVersion: String
    let buildNumber: String
    let iosVersion: String
    let deviceModel: String
    let locale: String
    let timeZone: String
}

// MARK: - QSOServiceRow

struct QSOServiceRow {
    let id: UUID
    let callsign: String
    let timestamp: Date
    let presence: [ServicePresenceRow]
}

// MARK: - ServicePresenceRow

struct ServicePresenceRow {
    // MARK: Lifecycle

    init(from presence: ServicePresence) {
        service = presence.serviceType
        isPresent = presence.isPresent
        needsUpload = presence.needsUpload
        uploadRejected = presence.uploadRejected
        isSubmitted = presence.isSubmitted
        lastConfirmedAt = presence.lastConfirmedAt
    }

    // MARK: Internal

    let service: ServiceType
    let isPresent: Bool
    let needsUpload: Bool
    let uploadRejected: Bool
    let isSubmitted: Bool
    let lastConfirmedAt: Date?
}

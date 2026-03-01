import CarrierWaveCore
import CoreLocation
import Foundation
import SwiftData

// MARK: - Session Completed Activity Reporting

extension LoggingSessionManager {
    /// Report a sessionCompleted activity when a logging session ends.
    /// Computes session stats from QSOs and reports to both local store and server.
    func reportSessionCompleted(_ session: LoggingSession) async {
        let sessionId = session.id

        // Fetch QSOs for this session, excluding metadata pseudo-modes
        var descriptor = FetchDescriptor<QSO>(
            predicate: #Predicate { $0.loggingSessionId == sessionId && !$0.isHidden }
        )
        descriptor.fetchLimit = 500
        guard let allQSOs = try? modelContext.fetch(descriptor) else {
            return
        }

        // Filter out metadata modes (WEATHER, SOLAR, NOTE)
        let qsos = allQSOs.filter { !Self.metadataModes.contains($0.mode.uppercased()) }

        // Skip if no real QSOs
        guard !qsos.isEmpty else {
            return
        }

        let details = buildSessionDetails(session: session, qsos: qsos)
        let callsign = session.myCallsign

        // Create local ActivityItem
        let item = ActivityItem(
            callsign: callsign,
            activityType: .sessionCompleted,
            timestamp: Date(),
            isOwn: true
        )
        item.details = details
        modelContext.insert(item)
        try? modelContext.save()

        // Report to server (if sharing is enabled)
        let sharingEnabled = UserDefaults.standard.object(forKey: "shareActivitiesEnabled") == nil
            || UserDefaults.standard.bool(forKey: "shareActivitiesEnabled")

        if sharingEnabled {
            let reporter = ActivityReporter()
            let request = buildReportRequest(details: details)
            let sourceURL = "https://activities.carrierwave.app"

            if let authToken = await reporter.client.ensureAuthToken() {
                do {
                    let response = try await reporter.client.reportActivity(
                        activity: request,
                        sourceURL: sourceURL,
                        authToken: authToken
                    )
                    item.serverId = response.id
                    try? modelContext.save()
                } catch {
                    print("Failed to report session activity: \(error.localizedDescription)")
                }
            }
        }

        // Notify UI
        NotificationCenter.default.post(
            name: .didDetectActivities,
            object: nil,
            userInfo: ["count": 1]
        )
    }

    // MARK: - Session Details Building

    func buildSessionDetails(
        session: LoggingSession,
        qsos: [QSO]
    ) -> ActivityDetails {
        var details = ActivityDetails()
        details.qsoCount = qsos.count

        // Duration
        if let endedAt = session.endedAt {
            let minutes = Int(endedAt.timeIntervalSince(session.startedAt) / 60)
            details.sessionDurationMinutes = max(minutes, 1)
        }

        // Bands, modes, DXCC
        details.sessionBands = Array(Set(qsos.map(\.band))).sorted()
        details.sessionModes = Array(Set(qsos.map(\.mode))).sorted()
        details.sessionDXCCCount = Set(qsos.compactMap(\.dxcc)).count

        // Distance and grid
        details.sessionMyGrid = session.myGrid
        details.sessionFarthestKm = computeFarthestDistance(
            myGrid: session.myGrid, qsos: qsos
        )

        // Activation type and park
        details.sessionActivationType = session.activationType.rawValue
        details.parkReference = session.parkReference
        if let parkRef = session.parkReference {
            details.parkName = POTAParksCache.shared.nameSync(for: parkRef)
        }

        // Equipment
        details.sessionRig = session.myRig
        details.sessionAntenna = session.myAntenna

        // Compact map and timeline data
        details.sessionContactGrids = buildContactGrids(from: qsos)
        details.sessionTimeline = buildTimeline(from: qsos)

        return details
    }

    /// Rebuild the ActivityItem for a session after batch edits (e.g., grid change).
    /// Finds the matching own sessionCompleted item and updates its details blob.
    static func rebuildSessionActivityItem(
        session: LoggingSession,
        qsos: [QSO],
        modelContext: ModelContext
    ) {
        let callsign = session.myCallsign
        let sessionStart = session.startedAt
        let typeRaw = ActivityType.sessionCompleted.rawValue

        var descriptor = FetchDescriptor<ActivityItem>(
            predicate: #Predicate {
                $0.isOwn
                    && $0.activityTypeRawValue == typeRaw
                    && $0.callsign == callsign
                    && $0.timestamp >= sessionStart
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        guard let item = try? modelContext.fetch(descriptor).first else {
            return
        }

        // Rebuild using an ephemeral manager just for the helper methods
        let manager = LoggingSessionManager(modelContext: modelContext)
        item.details = manager.buildSessionDetails(session: session, qsos: qsos)
        try? modelContext.save()
    }

    // MARK: - Private Helpers

    private func computeFarthestDistance(myGrid: String?, qsos: [QSO]) -> Double? {
        guard let myGrid, let myCoord = MaidenheadConverter.coordinate(from: myGrid) else {
            return nil
        }
        let myLoc = CLLocation(latitude: myCoord.latitude, longitude: myCoord.longitude)
        var farthestKm: Double = 0
        for qso in qsos {
            guard let theirGrid = qso.theirGrid,
                  let theirCoord = MaidenheadConverter.coordinate(from: theirGrid)
            else {
                continue
            }
            let theirLoc = CLLocation(
                latitude: theirCoord.latitude, longitude: theirCoord.longitude
            )
            farthestKm = max(farthestKm, myLoc.distance(from: theirLoc) / 1_000)
        }
        return farthestKm > 0 ? farthestKm : nil
    }

    private func buildContactGrids(from qsos: [QSO]) -> [ContactGridEntry]? {
        var entries: [ContactGridEntry] = []
        var seen = Set<String>()
        for qso in qsos {
            guard let grid = qso.theirGrid, !grid.isEmpty else {
                continue
            }
            let key = "\(grid):\(qso.band)"
            if seen.insert(key).inserted {
                entries.append(ContactGridEntry(grid: grid, band: qso.band))
            }
        }
        return entries.isEmpty ? nil : Array(entries.prefix(200))
    }

    private func buildTimeline(from qsos: [QSO]) -> [TimelineEntry]? {
        let sorted = qsos.sorted { $0.timestamp < $1.timestamp }
        let entries = sorted.prefix(200).map { qso in
            TimelineEntry(timestamp: qso.timestamp, band: qso.band)
        }
        return entries.isEmpty ? nil : entries
    }

    private func buildReportRequest(details: ActivityDetails) -> ReportActivityRequest {
        var reportDetails = ReportActivityDetails()
        reportDetails.qsoCount = details.qsoCount
        reportDetails.parkReference = details.parkReference
        reportDetails.parkName = details.parkName
        reportDetails.sessionDurationMinutes = details.sessionDurationMinutes
        reportDetails.sessionBands = details.sessionBands
        reportDetails.sessionModes = details.sessionModes
        reportDetails.sessionDXCCCount = details.sessionDXCCCount
        reportDetails.sessionFarthestKm = details.sessionFarthestKm
        reportDetails.sessionActivationType = details.sessionActivationType
        reportDetails.sessionMyGrid = details.sessionMyGrid
        reportDetails.sessionRig = details.sessionRig
        reportDetails.sessionAntenna = details.sessionAntenna
        reportDetails.sessionContactGrids = details.sessionContactGrids
        reportDetails.sessionTimeline = details.sessionTimeline

        return ReportActivityRequest(
            type: ActivityType.sessionCompleted.rawValue,
            timestamp: Date(),
            details: reportDetails
        )
    }
}

import CarrierWaveData
import Foundation
import SwiftData

@MainActor
final class ActivityReporter {
    // MARK: Lifecycle

    init(client: ActivitiesClient? = nil) {
        self.client = client ?? ActivitiesClient()
    }

    // MARK: Internal

    let client: ActivitiesClient

    /// Report detected activities to the server, storing server IDs on matching local items
    func reportActivities(
        _ activities: [DetectedActivity],
        sourceURL: String,
        modelContext: ModelContext? = nil
    ) async {
        // Check if user has opted out of sharing activities (default: share)
        if UserDefaults.standard.object(forKey: "shareActivitiesEnabled") != nil,
           !UserDefaults.standard.bool(forKey: "shareActivitiesEnabled")
        {
            return
        }

        guard let authToken = await client.ensureAuthToken() else {
            // Not authenticated, skip reporting
            return
        }

        for activity in activities {
            do {
                let request = buildRequest(from: activity)
                let response = try await client.reportActivity(
                    activity: request,
                    sourceURL: sourceURL,
                    authToken: authToken
                )
                // Store server ID on matching local ActivityItem
                if let modelContext {
                    setServerId(response.id, for: activity, in: modelContext)
                }
            } catch {
                // Log error but continue with other activities
                print("Failed to report activity: \(error.localizedDescription)")
            }
        }
    }

    /// Delete an activity from the server by its server ID
    func deleteActivity(
        serverId: UUID,
        sourceURL: String
    ) async throws {
        guard let authToken = await client.ensureAuthToken() else {
            return
        }

        try await client.deleteActivity(
            activityId: serverId,
            sourceURL: sourceURL,
            authToken: authToken
        )
    }

    // MARK: Private

    private func setServerId(
        _ serverId: UUID,
        for activity: DetectedActivity,
        in modelContext: ModelContext
    ) {
        let typeRaw = activity.type.rawValue
        let descriptor = FetchDescriptor<ActivityItem>(
            predicate: #Predicate {
                $0.isOwn && $0.activityTypeRawValue == typeRaw && $0.serverId == nil
            },
            sortBy: [SortDescriptor(\ActivityItem.timestamp, order: .reverse)]
        )
        if let item = (try? modelContext.fetch(descriptor))?.first(where: {
            abs($0.timestamp.timeIntervalSince(activity.timestamp)) < 60
        }) {
            item.serverId = serverId
            try? modelContext.save()
        }
    }

    private func buildRequest(from activity: DetectedActivity) -> ReportActivityRequest {
        var details = ReportActivityDetails()
        details.entityName = activity.entityName
        details.entityCode = activity.entityCode
        details.band = activity.band
        details.mode = activity.mode
        details.workedName = activity.workedName
        details.workedEntity = activity.workedEntity
        details.distanceKm = activity.distanceKm
        details.parkReference = activity.parkReference
        details.parkName = activity.parkName
        details.qsoCount = activity.qsoCount
        details.streakDays = activity.streakDays
        details.recordType = activity.recordType
        details.recordValue = activity.recordValue

        // Only include workedCallsign for workedFriend (both parties are app users).
        // For other types (dxContact, personalBest), strip it to avoid sending
        // third-party callsigns to the server without their consent.
        if activity.type == .workedFriend {
            details.workedCallsign = activity.workedCallsign
        }

        return ReportActivityRequest(
            type: activity.type.rawValue,
            timestamp: activity.timestamp,
            details: details
        )
    }
}

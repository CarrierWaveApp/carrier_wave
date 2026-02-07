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

    /// Report detected activities to the server
    func reportActivities(_ activities: [DetectedActivity], sourceURL: String) async {
        guard let authToken = try? client.getAuthToken() else {
            // Not authenticated, skip reporting
            return
        }

        for activity in activities {
            do {
                let request = buildRequest(from: activity)
                _ = try await client.reportActivity(
                    activity: request,
                    sourceURL: sourceURL,
                    authToken: authToken
                )
            } catch {
                // Log error but continue with other activities
                print("Failed to report activity: \(error.localizedDescription)")
            }
        }
    }

    // MARK: Private

    private func buildRequest(from activity: DetectedActivity) -> ReportActivityRequest {
        var details = ReportActivityDetails()
        details.entityName = activity.entityName
        details.entityCode = activity.entityCode
        details.band = activity.band
        details.mode = activity.mode
        details.workedCallsign = activity.workedCallsign
        details.distanceKm = activity.distanceKm
        details.parkReference = activity.parkReference
        details.parkName = activity.parkName
        details.qsoCount = activity.qsoCount
        details.streakDays = activity.streakDays
        details.recordType = activity.recordType
        details.recordValue = activity.recordValue

        return ReportActivityRequest(
            type: activity.type.rawValue,
            timestamp: activity.timestamp,
            details: details
        )
    }
}

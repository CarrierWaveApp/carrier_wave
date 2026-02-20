import Combine
import Foundation
import SwiftData

// MARK: - ActivityFeedSyncService

@MainActor
final class ActivityFeedSyncService: ObservableObject {
    // MARK: Lifecycle

    init(modelContext: ModelContext, client: ActivitiesClient? = nil) {
        self.modelContext = modelContext
        self.client = client ?? ActivitiesClient()
    }

    // MARK: Internal

    @Published var isSyncing = false
    @Published var syncError: String?

    let modelContext: ModelContext
    let client: ActivitiesClient

    /// Sync activity feed from server
    func syncFeed(sourceURL: String, filter: FeedFilterType? = nil) async throws {
        guard let authToken = await client.ensureAuthToken() else {
            throw ActivityFeedSyncError.notAuthenticated
        }

        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        let response = try await client.getFeed(
            sourceURL: sourceURL,
            authToken: authToken,
            filter: filter,
            limit: 100
        )

        try updateLocalActivities(from: response.items)
    }

    // MARK: Private

    private func updateLocalActivities(from items: [FeedItemDTO]) throws {
        let descriptor = FetchDescriptor<ActivityItem>(
            predicate: #Predicate { !$0.isOwn }
        )
        let existing = try modelContext.fetch(descriptor)
        let existingById = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

        for item in items {
            guard existingById[item.id] == nil,
                  let activityType = ActivityType(rawValue: item.activityType)
            else {
                continue
            }

            let activityItem = ActivityItem(
                id: item.id,
                callsign: item.callsign,
                activityType: activityType,
                timestamp: item.timestamp,
                isOwn: false
            )
            activityItem.details = convertDetails(from: item.details)
            modelContext.insert(activityItem)
        }

        try modelContext.save()
    }

    private func convertDetails(from dto: ReportActivityDetails) -> ActivityDetails {
        var details = ActivityDetails()
        details.entityName = dto.entityName
        details.entityCode = dto.entityCode
        details.band = dto.band
        details.mode = dto.mode
        details.workedCallsign = dto.workedCallsign
        details.distanceKm = dto.distanceKm
        details.parkReference = dto.parkReference
        details.parkName = dto.parkName
        details.qsoCount = dto.qsoCount
        details.streakDays = dto.streakDays
        details.challengeName = dto.challengeName
        details.tierName = dto.tierName
        details.recordType = dto.recordType
        details.recordValue = dto.recordValue
        details.sessionDurationMinutes = dto.sessionDurationMinutes
        details.sessionBands = dto.sessionBands
        details.sessionModes = dto.sessionModes
        details.sessionDXCCCount = dto.sessionDXCCCount
        details.sessionFarthestKm = dto.sessionFarthestKm
        details.sessionActivationType = dto.sessionActivationType
        details.sessionMyGrid = dto.sessionMyGrid
        details.sessionRig = dto.sessionRig
        details.sessionAntenna = dto.sessionAntenna
        details.sessionContactGrids = dto.sessionContactGrids
        details.sessionTimeline = dto.sessionTimeline
        return details
    }
}

// MARK: - ActivityFeedSyncError

enum ActivityFeedSyncError: LocalizedError {
    case notAuthenticated
    case syncFailed(String)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "Please sign in to view activity feed"
        case let .syncFailed(message):
            "Feed sync failed: \(message)"
        }
    }
}

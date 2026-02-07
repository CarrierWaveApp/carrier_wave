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
        guard let authToken = try? client.getAuthToken() else {
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
        // Fetch existing activity items (not own)
        let descriptor = FetchDescriptor<ActivityItem>(
            predicate: #Predicate { !$0.isOwn }
        )
        let existing = try modelContext.fetch(descriptor)
        let existingById = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

        var seenIds = Set<UUID>()

        for item in items {
            seenIds.insert(item.id)

            if existingById[item.id] != nil {
                // Already have this item, skip
                continue
            }

            // Create new activity item
            guard let activityType = ActivityType(rawValue: item.activityType) else {
                continue
            }

            let activityItem = ActivityItem(
                id: item.id,
                callsign: item.callsign,
                activityType: activityType,
                timestamp: item.timestamp,
                isOwn: false
            )

            // Convert details
            var details = ActivityDetails()
            details.entityName = item.details.entityName
            details.entityCode = item.details.entityCode
            details.band = item.details.band
            details.mode = item.details.mode
            details.workedCallsign = item.details.workedCallsign
            details.distanceKm = item.details.distanceKm
            details.parkReference = item.details.parkReference
            details.parkName = item.details.parkName
            details.qsoCount = item.details.qsoCount
            details.streakDays = item.details.streakDays
            details.challengeName = item.details.challengeName
            details.tierName = item.details.tierName
            details.recordType = item.details.recordType
            details.recordValue = item.details.recordValue

            activityItem.details = details
            modelContext.insert(activityItem)
        }

        // Optionally remove old items not in the latest fetch
        // (for now, keep them - server will handle retention)

        try modelContext.save()
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

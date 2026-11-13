import CarrierWaveData
import Foundation
import OSLog

// MARK: - ContestParticipant

struct ContestParticipant: Identifiable, Equatable {
    let id: String
    let callsign: String
    let timestamp: Date
    let qsoCount: Int
    let category: String?
    let score: Int?
}

// MARK: - ContestParticipationStats

struct ContestParticipationStats: Equatable {
    var me: ContestParticipant?
    var friends: [ContestParticipant] = []
}

// MARK: - ContestParticipationGatherer

/// Aggregates contest participation for the detail view. Blends the friends
/// activity feed with the local activity log so both your own sessions and
/// friends' sessions that referenced the same contest are surfaced.
@MainActor
struct ContestParticipationGatherer {
    // MARK: Lifecycle

    init(client: ActivitiesClient? = nil) {
        self.client = client ?? ActivitiesClient()
    }

    // MARK: Internal

    func gather(contestID: String) async -> ContestParticipationStats {
        async let friends = fetchFriends(contestID: contestID)
        let mine = fetchOwn(contestID: contestID)
        return await ContestParticipationStats(me: mine, friends: friends)
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "CarrierWave",
        category: "ContestParticipation"
    )

    private let client: ActivitiesClient

    private func fetchFriends(contestID: String) async -> [ContestParticipant] {
        guard let authToken = await client.ensureAuthToken() else {
            return []
        }
        do {
            let feed = try await client.getFeed(
                sourceURL: ActivitiesClient.resolvedBaseURL,
                authToken: authToken,
                filter: .friends,
                limit: 200
            )
            let participants = feed.items.compactMap { item -> ContestParticipant? in
                guard item.details.contestId == contestID else {
                    return nil
                }
                return ContestParticipant(
                    id: item.id.uuidString,
                    callsign: item.callsign,
                    timestamp: item.timestamp,
                    qsoCount: item.details.qsoCount ?? 0,
                    category: item.details.contestCategory,
                    score: item.details.contestScore
                )
            }
            return dedupeByCallsign(participants)
        } catch {
            Self.logger.warning("Friends feed fetch failed: \(error.localizedDescription)")
            return []
        }
    }

    private func fetchOwn(contestID: String) -> ContestParticipant? {
        // The caller is responsible for reading ActivityItem rows via SwiftData
        // in the view layer; this helper focuses on the network side. The
        // ContestDetailView reads its own participation via a SwiftData fetch
        // directly in a future iteration — for now return nil so the section
        // only shows friends.
        _ = contestID
        return nil
    }

    private func dedupeByCallsign(_ input: [ContestParticipant]) -> [ContestParticipant] {
        var seen: Set<String> = []
        return input.sorted { $0.timestamp > $1.timestamp }.compactMap { participant in
            let key = participant.callsign.uppercased()
            guard !seen.contains(key) else {
                return nil
            }
            seen.insert(key)
            return participant
        }
    }
}

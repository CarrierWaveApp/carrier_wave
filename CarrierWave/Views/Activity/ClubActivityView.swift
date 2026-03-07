import CarrierWaveData
import SwiftUI

// MARK: - ClubActivityView

struct ClubActivityView: View {
    // MARK: Internal

    let club: Club

    var body: some View {
        Group {
            if activities.isEmpty, !isLoading {
                ContentUnavailableView(
                    "No Activity",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text(
                        "Club member activity will appear here"
                    )
                )
            } else if activities.isEmpty, isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(activities) { item in
                            ClubActivityItemRow(item: item)
                        }
                        if hasMore {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .task { await loadMore() }
                        }
                    }
                    .padding()
                }
            }
        }
        .task { await loadInitial() }
    }

    // MARK: Private

    @State private var activities: [ClubActivityItemDTO] = []
    @State private var isLoading = false
    @State private var nextCursor: String?
    @State private var hasMore = true

    private let pageSize = 20
    private let sourceURL = "https://activities.carrierwave.app"

    private func loadInitial() async {
        guard !isLoading else {
            return
        }
        isLoading = true
        defer { isLoading = false }

        let client = ActivitiesClient()
        guard let authToken = await client.ensureAuthToken()
        else {
            hasMore = false
            return
        }

        do {
            let response = try await client.fetchClubActivity(
                clubId: club.serverId,
                sourceURL: sourceURL,
                authToken: authToken,
                limit: pageSize
            )
            activities = response.items
            hasMore = response.pagination.hasMore
            nextCursor = response.pagination.nextCursor
        } catch {
            hasMore = false
        }
    }

    private func loadMore() async {
        guard !isLoading, hasMore, let nextCursor else {
            return
        }
        isLoading = true
        defer { isLoading = false }

        let client = ActivitiesClient()
        guard let authToken = await client.ensureAuthToken()
        else {
            hasMore = false
            return
        }

        do {
            let response = try await client.fetchClubActivity(
                clubId: club.serverId,
                sourceURL: sourceURL,
                authToken: authToken,
                cursor: nextCursor,
                limit: pageSize
            )
            activities.append(contentsOf: response.items)
            hasMore = response.pagination.hasMore
            self.nextCursor = response.pagination.nextCursor
        } catch {
            hasMore = false
        }
    }
}

// MARK: - ClubActivityItemRow

struct ClubActivityItemRow: View {
    // MARK: Internal

    let item: ClubActivityItemDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Image(systemName: activityIcon)
                    .font(.title3)
                    .foregroundStyle(iconColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(item.callsign)
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        Spacer()

                        Text(item.timestamp, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(activityDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let detailText {
                HStack {
                    Text(detailText)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    // MARK: Private

    private var parsedType: ActivityType? {
        ActivityType(rawValue: item.activityType)
    }

    private var activityIcon: String {
        parsedType?.icon ?? "wave.3.right"
    }

    private var iconColor: Color {
        guard let actType = parsedType else {
            return .gray
        }
        switch actType {
        case .challengeTierUnlock,
             .challengeCompletion:
            return .yellow
        case .newDXCCEntity:
            return .blue
        case .newBand,
             .newMode:
            return .purple
        case .dxContact:
            return .green
        case .potaActivation:
            return .green
        case .sotaActivation:
            return .orange
        case .dailyStreak,
             .potaDailyStreak:
            return .orange
        case .personalBest:
            return .red
        case .workedFriend:
            return .cyan
        case .sessionCompleted:
            return .indigo
        }
    }

    private var activityDescription: String {
        let details = item.details

        guard let actType = parsedType else {
            return formatFallbackType(item.activityType)
        }

        switch actType {
        case .challengeTierUnlock:
            if let tier = details.tierName,
               let challenge = details.challengeName
            {
                return "Reached \(tier) in \(challenge)"
            }
            return "Unlocked a new tier"

        case .challengeCompletion:
            if let challenge = details.challengeName {
                return "Completed \(challenge)"
            }
            return "Completed a challenge"

        case .newDXCCEntity:
            if let entity = details.entityName {
                return "Worked \(entity) for the first time"
            }
            return "Worked a new DXCC entity"

        case .newBand:
            if let band = details.band {
                return "Made first \(band) contact"
            }
            return "Made contact on a new band"

        case .newMode:
            if let mode = details.mode {
                return "Made first \(mode) contact"
            }
            return "Made contact with a new mode"

        case .dxContact:
            if let callsign = details.workedCallsign,
               let distance = details.distanceKm
            {
                let distanceStr = UnitFormatter.distance(distance)
                return "Worked \(callsign) (\(distanceStr))"
            }
            return "Made a DX contact"

        case .potaActivation:
            if let park = details.parkReference,
               let count = details.qsoCount
            {
                return "Activated \(park) (\(count) QSOs)"
            }
            return "Completed a POTA activation"

        case .sotaActivation:
            if let summit = details.parkReference,
               let count = details.qsoCount
            {
                return "Activated \(summit) (\(count) QSOs)"
            }
            return "Completed a SOTA activation"

        case .dailyStreak:
            if let days = details.streakDays {
                return "Hit a \(days)-day QSO streak"
            }
            return "Extended daily streak"

        case .potaDailyStreak:
            if let days = details.streakDays {
                return "Hit a \(days)-day POTA streak"
            }
            return "Extended POTA streak"

        case .personalBest:
            if let recordType = details.recordType,
               let value = details.recordValue
            {
                return "New \(recordType) record: \(value)"
            }
            return "Set a new personal best"

        case .workedFriend:
            if let callsign = details.workedCallsign {
                return "Worked friend \(callsign)"
            }
            return "Worked a friend"

        case .sessionCompleted:
            if let count = details.qsoCount {
                return "Completed a session (\(count) QSOs)"
            }
            return "Completed a session"
        }
    }

    private var detailText: String? {
        let details = item.details
        var parts: [String] = []

        if let band = details.band {
            parts.append(band)
        }
        if let mode = details.mode {
            parts.append(mode)
        }

        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    private func formatFallbackType(_ type: String) -> String {
        type
            .replacingOccurrences(
                of: "([a-z])([A-Z])",
                with: "$1 $2",
                options: .regularExpression
            )
            .capitalized
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ClubActivityView(
            club: Club(
                serverId: UUID(),
                name: "Preview Club"
            )
        )
    }
    .modelContainer(
        for: [Club.self, ClubMember.self],
        inMemory: true
    )
}

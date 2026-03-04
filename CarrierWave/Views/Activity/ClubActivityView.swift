import CarrierWaveData
import SwiftData
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
            } else {
                List {
                    ForEach(activities) { item in
                        ClubActivityRow(item: item)
                    }
                    if hasMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .task { await loadMore() }
                    }
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

// MARK: - ClubActivityRow

struct ClubActivityRow: View {
    // MARK: Internal

    let item: ClubActivityItemDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.callsign)
                    .font(.body)
                    .fontWeight(.medium)
                Spacer()
                Text(item.timestamp, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            activityDescription
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: Private

    @ViewBuilder
    private var activityDescription: some View {
        let details = item.details
        switch item.activityType {
        case "qsoLogged":
            if let worked = details.workedCallsign {
                Text(
                    "QSO with \(worked)"
                        + bandModeLabel(details)
                )
            } else {
                Text(
                    "Logged a QSO" + bandModeLabel(details)
                )
            }
        case "parkActivation":
            if let park = details.parkName {
                Text("Activated \(park)")
            } else if let ref = details.parkReference {
                Text("Activated \(ref)")
            } else {
                Text("Park activation")
            }
        case "sessionCompleted":
            if let count = details.qsoCount {
                Text(
                    "Session: \(count) QSO\(count == 1 ? "" : "s")"
                        + bandModeLabel(details)
                )
            } else {
                Text("Completed a session")
            }
        default:
            Text(formatActivityType(item.activityType))
        }
    }

    private func bandModeLabel(
        _ details: ReportActivityDetails
    ) -> String {
        let parts = [details.band, details.mode]
            .compactMap { $0 }
        if parts.isEmpty {
            return ""
        }
        return " on \(parts.joined(separator: " "))"
    }

    private func formatActivityType(_ type: String) -> String {
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

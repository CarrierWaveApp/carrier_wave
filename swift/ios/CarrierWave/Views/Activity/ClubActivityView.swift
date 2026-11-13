import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - ClubActivityView

struct ClubActivityView: View {
    // MARK: Internal

    let club: FfiClub

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
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(activities, id: \.id) { item in
                            ClubActivityRow(item: item)
                        }
                        if hasMore {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .task { await loadMore() }
                        }
                    }
                    .padding()
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .task { await loadInitial() }
    }

    // MARK: Private

    @State private var activities: [FfiClubActivityItem] = []
    @State private var isLoading = false
    @State private var nextCursor: String?
    @State private var hasMore = true

    private func loadInitial() async {
        guard !isLoading else {
            return
        }
        isLoading = true
        defer { isLoading = false }

        guard let clubId = UUID(uuidString: club.id) else {
            hasMore = false
            return
        }

        do {
            let page = try await ClubsSyncService.shared.fetchActivity(clubId: clubId, cursor: nil)
            activities = page.items
            hasMore = page.hasMore
            nextCursor = page.nextCursor
        } catch {
            hasMore = false
        }
    }

    private func loadMore() async {
        guard !isLoading, hasMore, let cursor = nextCursor else {
            return
        }
        guard let clubId = UUID(uuidString: club.id) else {
            hasMore = false
            return
        }
        isLoading = true
        defer { isLoading = false }

        do {
            let page = try await ClubsSyncService.shared.fetchActivity(
                clubId: clubId,
                cursor: cursor
            )
            activities.append(contentsOf: page.items)
            hasMore = page.hasMore
            nextCursor = page.nextCursor
        } catch {
            hasMore = false
        }
    }
}

// MARK: - ClubActivityRow

struct ClubActivityRow: View {
    // MARK: Internal

    let item: FfiClubActivityItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Image(systemName: resolvedType?.icon ?? "bubble.left.fill")
                    .font(.title3)
                    .foregroundStyle(iconColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(item.callsign)
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        Spacer()

                        Text(timestamp, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(activityDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    // MARK: Private

    private var timestamp: Date {
        Date(timeIntervalSince1970: TimeInterval(item.timestamp))
    }

    private var resolvedType: ActivityType? {
        ActivityType(rawValue: item.activityType)
    }

    private var iconColor: Color {
        guard let resolved = resolvedType else {
            return .gray
        }
        switch resolved {
        case .newDXCCEntity: return .blue
        case .newBand,
             .newMode: return .purple
        case .dxContact: return .green
        case .potaActivation: return .green
        case .sotaActivation: return .orange
        case .dailyStreak,
             .potaDailyStreak: return .orange
        case .personalBest: return .red
        case .workedFriend: return .cyan
        case .sessionCompleted: return .indigo
        }
    }

    private var activityDescription: String {
        formatActivityType(item.activityType)
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
            club: FfiClub(
                id: UUID().uuidString,
                name: "Preview Club",
                callsign: nil,
                description: nil,
                notesUrl: nil,
                notesTitle: nil,
                hasLogo: false,
                cachedMemberCount: 0,
                lastSyncedAt: 0
            )
        )
    }
}

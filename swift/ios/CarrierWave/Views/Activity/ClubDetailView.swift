import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - ClubDetailView

struct ClubDetailView: View {
    // MARK: Internal

    let club: FfiClub

    var body: some View {
        VStack(spacing: 0) {
            Picker("Tab", selection: $selectedTab) {
                ForEach(ClubTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            switch selectedTab {
            case .members:
                membersList
            case .activity:
                ClubActivityView(club: club)
            case .map:
                ClubMapView(
                    club: club,
                    memberStatuses: memberStatuses
                )
            }
        }
        .navigationTitle(club.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await refresh() }
                } label: {
                    if isRefreshing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(isRefreshing)
            }
        }
        .task {
            loadFriendMembers()
            loadMemberPage()
            await loadStatuses()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { showingError = false }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab: ClubTab = .members
    @State private var memberStatuses: [String: FfiMemberStatus] = [:]
    @State private var friendMemberCallsigns: [String] = []
    @State private var loadedMembers: [FfiClubMember] = []
    @State private var allMembersFull: [FfiClubMember] = []
    @State private var hasMoreMembers = false
    @State private var isRefreshing = false
    @State private var errorMessage: String?
    @State private var showingError = false

    private let sourceURL = ActivitiesClient.resolvedBaseURL
    private let pageSize = 100
    /// Cap status queries to avoid N+1 on the server for huge clubs
    private let statusMemberCap = 200

    private var membersList: some View {
        List {
            if club.hasLogo {
                Section {
                    HStack {
                        Spacer()
                        ClubLogoView(club: club, size: 64)
                        Spacer()
                    }
                }
                .listRowBackground(Color.clear)
            }

            ClubStatsView(
                club: club,
                memberStatuses: memberStatuses
            )

            if let description = club.description,
               !description.isEmpty
            {
                Section("About") {
                    Text(description)
                        .font(.body)
                }
            }

            if !friendMemberCallsigns.isEmpty {
                Section("Friends (\(friendMemberCallsigns.count))") {
                    ForEach(friendMemberCallsigns, id: \.self) { callsign in
                        FriendMemberRow(
                            callsign: callsign,
                            status: memberStatuses[callsign.uppercased()]
                        )
                    }
                }
            }

            Section("Members (\(Int(club.cachedMemberCount)))") {
                if loadedMembers.isEmpty, friendMemberCallsigns.isEmpty {
                    Text("No members loaded")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(loadedMembers, id: \.callsign) { member in
                        MemberRow(
                            member: member,
                            status: memberStatuses[
                                member.callsign.uppercased()
                            ]
                        )
                    }
                    if hasMoreMembers {
                        Button("Load More") {
                            loadMemberPage()
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.blue)
                    }
                }
            }
        }
    }

    // MARK: - Data Loading

    /// Find friends in this club using the in-memory membership cache.
    /// No SwiftData fetch required — works even for 30K-member clubs
    /// whose ClubMember records haven't been synced to the device.
    private func loadFriendMembers() {
        let friends = FriendsSyncService.shared.acceptedFriends
        let friendCallsigns = Set(
            friends.map { $0.friendCallsign.uppercased() }
        )

        guard !friendCallsigns.isEmpty else {
            friendMemberCallsigns = []
            return
        }

        // Intersect friend callsigns with club membership from cache
        let clubCallsigns = ClubsSyncService.shared.callsigns(
            inClub: club.name
        )
        friendMemberCallsigns = friendCallsigns
            .intersection(clubCallsigns)
            .sorted()
    }

    /// Load the next page of members from the service, excluding friends
    /// (shown in their own section). Fetches full list once, then paginates.
    private func loadMemberPage() {
        Task { @MainActor in
            if allMembersFull.isEmpty {
                let fetched = await ClubsSyncService.shared.members(inClubId: club.id)
                let friendSet = Set(friendMemberCallsigns.map { $0.uppercased() })
                allMembersFull = fetched
                    .filter { !friendSet.contains($0.callsign.uppercased()) }
                    .sorted { $0.callsign < $1.callsign }
            }
            let offset = loadedMembers.count
            let end = min(offset + pageSize, allMembersFull.count)
            guard offset < end else {
                return
            }
            loadedMembers.append(contentsOf: allMembersFull[offset ..< end])
            hasMoreMembers = loadedMembers.count < allMembersFull.count
        }
    }

    private func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        guard let clubId = UUID(uuidString: club.id) else {
            return
        }

        do {
            try await ClubsSyncService.shared.syncClubDetails(
                clubId: clubId,
                sourceURL: sourceURL
            )
            // Reload after sync
            loadedMembers = []
            allMembersFull = []
            loadFriendMembers()
            loadMemberPage()
            await loadStatuses()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    /// Load on-air/active statuses. Skipped for very large clubs
    /// to avoid N+1 spot queries on the server.
    private func loadStatuses() async {
        guard Int(club.cachedMemberCount) <= statusMemberCap else {
            return
        }
        guard let clubId = UUID(uuidString: club.id) else {
            return
        }

        do {
            let statuses = try await ClubsSyncService.shared.fetchStatus(clubId: clubId)
            var map: [String: FfiMemberStatus] = [:]
            for status in statuses {
                map[status.callsign.uppercased()] = status
            }
            memberStatuses = map
        } catch {
            // Status is best-effort, don't show errors
        }
    }
}

// MARK: - ClubTab

enum ClubTab: String, CaseIterable {
    case members = "Members"
    case activity = "Activity"
    case map = "Map"
}

// MARK: - FriendMemberRow

/// Lightweight row for friend members identified via the in-memory cache.
/// Doesn't require a FfiClubMember object — just the callsign.
struct FriendMemberRow: View {
    // MARK: Internal

    let callsign: String
    var status: FfiMemberStatus?

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            Text(callsign)
                .font(.body)
                .fontWeight(.medium)

            Spacer()

            if let spot = status?.spot {
                HStack(spacing: 4) {
                    Text(formatFrequency(spot.frequency))
                        .font(.caption)
                        .foregroundStyle(.green)
                    if let mode = spot.mode {
                        Text(mode)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: Private

    private var statusColor: Color {
        switch status?.status {
        case .onAir: .green
        case .recentlyActive: .yellow
        case .inactive,
             .none: Color(.systemGray4)
        }
    }

    private func formatFrequency(_ khz: Double) -> String {
        let mhz = khz / 1_000.0
        return String(format: "%.3f", mhz)
    }
}

// MARK: - MemberRow

struct MemberRow: View {
    // MARK: Internal

    let member: FfiClubMember
    var status: FfiMemberStatus?

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(member.callsign)
                        .font(.body)
                        .fontWeight(.medium)
                    if member.role == "admin" {
                        Text("Admin")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                if let grid = member.lastGrid {
                    Text(grid)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let spot = status?.spot {
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(formatFrequency(spot.frequency))
                            .font(.caption)
                            .foregroundStyle(.green)
                        if let mode = spot.mode {
                            Text(mode)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(Date(timeIntervalSince1970: TimeInterval(spot.spottedAt)), style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if let lastSeenTs = status?.lastSeenAt {
                Text(Date(timeIntervalSince1970: TimeInterval(lastSeenTs)), style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Private

    private var statusColor: Color {
        switch status?.status {
        case .onAir: .green
        case .recentlyActive: .yellow
        case .inactive,
             .none: Color(.systemGray4)
        }
    }

    private func formatFrequency(_ khz: Double) -> String {
        let mhz = khz / 1_000.0
        return String(format: "%.3f", mhz)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ClubDetailView(
            club: FfiClub(
                id: UUID().uuidString,
                name: "Pacific Northwest DX Club",
                callsign: nil,
                description: "A club for DXers in the PNW",
                notesUrl: nil,
                notesTitle: nil,
                hasLogo: false,
                cachedMemberCount: 0,
                lastSyncedAt: 0
            )
        )
    }
}

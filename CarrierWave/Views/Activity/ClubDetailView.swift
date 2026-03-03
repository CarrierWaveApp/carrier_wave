import SwiftData
import SwiftUI

// MARK: - ClubDetailView

struct ClubDetailView: View {
    // MARK: Internal

    let club: Club

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
            await refreshQuietly()
            await loadStatuses()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { showingError = false }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
    }

    // MARK: Private

    @State private var selectedTab: ClubTab = .members
    @State private var memberStatuses: [String: MemberStatusDTO] = [:]
    @State private var isRefreshing = false
    @State private var errorMessage: String?
    @State private var showingError = false

    private let sourceURL = "https://activities.carrierwave.app"

    /// Sort: admins first, then alphabetical
    private var sortedMembers: [ClubMember] {
        club.members.sorted { first, second in
            if first.role != second.role {
                return first.role == "admin"
            }
            return first.callsign < second.callsign
        }
    }

    private var membersList: some View {
        List {
            ClubStatsView(
                club: club,
                memberStatuses: memberStatuses
            )

            if let description = club.clubDescription,
               !description.isEmpty
            {
                Section("About") {
                    Text(description)
                        .font(.body)
                }
            }

            Section("Members (\(club.memberCount))") {
                if club.members.isEmpty {
                    Text("No members loaded")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedMembers, id: \.callsign) { member in
                        MemberRow(
                            member: member,
                            status: memberStatuses[
                                member.callsign.uppercased()
                            ]
                        )
                    }
                }
            }
        }
    }

    private func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            try await ClubsSyncService.shared.syncClubDetails(
                clubId: club.serverId,
                sourceURL: sourceURL
            )
            await loadStatuses()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    /// Sync club details on appear without showing errors
    private func refreshQuietly() async {
        try? await ClubsSyncService.shared.syncClubDetails(
            clubId: club.serverId,
            sourceURL: sourceURL
        )
    }

    private func loadStatuses() async {
        let client = ActivitiesClient()
        guard let authToken = await client.ensureAuthToken()
        else {
            return
        }

        do {
            let statuses = try await client.fetchClubStatus(
                clubId: club.serverId,
                sourceURL: sourceURL,
                authToken: authToken
            )
            var map: [String: MemberStatusDTO] = [:]
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

// MARK: - MemberRow

struct MemberRow: View {
    // MARK: Internal

    let member: ClubMember
    var status: MemberStatusDTO?

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

            if let spotInfo = status?.spotInfo {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatFrequency(spotInfo.frequency))
                        .font(.caption)
                        .foregroundStyle(.green)
                    if let mode = spotInfo.mode {
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

// MARK: - Preview

#Preview {
    NavigationStack {
        ClubDetailView(
            club: Club(
                serverId: UUID(),
                name: "Pacific Northwest DX Club",
                clubDescription: "A club for DXers in the PNW"
            )
        )
    }
    .modelContainer(
        for: [Club.self, ClubMember.self],
        inMemory: true
    )
}

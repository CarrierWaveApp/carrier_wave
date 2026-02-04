import SwiftData
import SwiftUI

// MARK: - ActivityView

struct ActivityView: View {
    // MARK: Internal

    let tourState: TourState

    /// When true, the view is already inside a navigation context
    var isInNavigationContext: Bool = false

    @Environment(\.modelContext) var modelContext
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    var body: some View {
        if isInNavigationContext {
            activityContent
        } else {
            NavigationStack {
                activityContent
            }
        }
    }

    // MARK: Private

    @State private var isRefreshing = false

    @Query(sort: \ChallengeParticipation.joinedAt, order: .reverse)
    private var allParticipations: [ChallengeParticipation]

    @Query(sort: \ActivityItem.timestamp, order: .reverse)
    private var allActivityItems: [ActivityItem]

    @Query private var clubs: [Club]

    @Query(filter: #Predicate<Friendship> { $0.statusRawValue == "accepted" })
    private var acceptedFriends: [Friendship]

    @State private var selectedFilter: FeedFilter = .all

    @State private var syncService: ChallengesSyncService?
    @State private var friendsSyncService: FriendsSyncService?
    @State private var clubsSyncService: ClubsSyncService?
    @State private var feedSyncService: ActivityFeedSyncService?
    @State private var errorMessage: String?
    @State private var showingError = false

    // Invite handling
    @State private var pendingInvite: PendingChallengeInvite?
    @State private var showingInviteSheet = false
    @State private var isJoiningFromInvite = false

    // Sharing
    @State private var itemToShare: ActivityItem?
    @State private var showingShareSheet = false
    @State private var showingSummarySheet = false

    // Friend profile navigation
    @State private var selectedCallsign: String?
    @State private var showingFriendProfile = false
    @State private var showingOwnProfile = false

    // Friend invite handling
    @State private var pendingFriendInviteToken: String?
    @State private var showingFriendInviteSheet = false
    @State private var isProcessingFriendInvite = false

    private var activeParticipations: [ChallengeParticipation] {
        allParticipations.filter { $0.status == .active }
    }

    private var completedParticipations: [ChallengeParticipation] {
        allParticipations.filter { $0.status == .completed }
    }

    private var currentCallsign: String {
        // Try to get from keychain first
        if let callsign = try? KeychainHelper.shared.readString(
            for: KeychainHelper.Keys.currentCallsign
        ),
            !callsign.isEmpty
        {
            return callsign
        }
        // Fall back to "Me" if not configured
        return "Me"
    }

    private var filteredActivityItems: [ActivityItem] {
        switch selectedFilter {
        case .all:
            return allActivityItems
        case .friends:
            let friendCallsigns = Set(acceptedFriends.map { $0.friendCallsign.uppercased() })
            return allActivityItems.filter { friendCallsigns.contains($0.callsign.uppercased()) }
        case let .club(clubId):
            guard let club = clubs.first(where: { $0.id == clubId }) else {
                return []
            }
            return allActivityItems.filter { club.isMember(callsign: $0.callsign) }
        }
    }

    private var activityContent: some View {
        ScrollView {
            if horizontalSizeClass == .regular {
                // iPad: Side-by-side layout
                HStack(alignment: .top, spacing: 24) {
                    challengesSection
                        .frame(minWidth: 300, idealWidth: 350, maxWidth: 400)
                    activityFeedSection
                        .frame(maxWidth: .infinity)
                }
                .padding()
            } else {
                // iPhone: Vertical stack
                VStack(spacing: 24) {
                    challengesSection
                    activityFeedSection
                }
                .padding()
            }
        }
        .navigationTitle("Activity")
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                NavigationLink {
                    FriendsListView()
                } label: {
                    Image(systemName: "person.2")
                }
                .accessibilityLabel("Friends")

                NavigationLink {
                    ClubsListView()
                } label: {
                    Image(systemName: "person.3")
                }
                .accessibilityLabel("Clubs")
            }
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
                .accessibilityLabel("Refresh")
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    showingOwnProfile = true
                } label: {
                    Label("My Profile", systemImage: "person.circle")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    showingSummarySheet = true
                } label: {
                    Label("Share Summary", systemImage: "square.and.arrow.up")
                }
            }
        }
        .navigationDestination(isPresented: $showingOwnProfile) {
            FriendProfileView(
                callsign: currentCallsign,
                friendship: nil,
                isOwnProfile: true
            )
        }
        .onAppear {
            if syncService == nil {
                syncService = ChallengesSyncService(modelContext: modelContext)
            }
            if friendsSyncService == nil {
                friendsSyncService = FriendsSyncService(modelContext: modelContext)
            }
            if clubsSyncService == nil {
                clubsSyncService = ClubsSyncService(modelContext: modelContext)
            }
            if feedSyncService == nil {
                feedSyncService = ActivityFeedSyncService(modelContext: modelContext)
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { showingError = false }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
        .sheet(isPresented: $showingInviteSheet) {
            if let invite = pendingInvite {
                InviteJoinSheet(
                    invite: invite,
                    syncService: syncService,
                    isJoining: $isJoiningFromInvite,
                    onComplete: { success in
                        showingInviteSheet = false
                        pendingInvite = nil
                        if !success {
                            errorMessage = "Failed to join challenge"
                            showingError = true
                        }
                    }
                )
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let item = itemToShare {
                ShareSheetView(item: item)
            }
        }
        .sheet(isPresented: $showingSummarySheet) {
            SummaryCardSheet(callsign: currentCallsign)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .didReceiveChallengeInvite)
        ) { notification in
            handleInviteNotification(notification)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .didSyncQSOs)
        ) { _ in
            Task { await evaluateNewQSOs() }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .didReceiveFriendInvite)
        ) { notification in
            handleFriendInviteNotification(notification)
        }
        .sheet(isPresented: $showingFriendInviteSheet) {
            FriendInviteConfirmSheet(
                token: pendingFriendInviteToken ?? "",
                isProcessing: $isProcessingFriendInvite,
                onAccept: { acceptFriendInvite() },
                onDismiss: {
                    showingFriendInviteSheet = false
                    pendingFriendInviteToken = nil
                }
            )
        }
        .miniTour(.challenges, tourState: tourState)
    }

    // MARK: - Challenges Section

    private var challengesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your Challenges")
                    .font(.headline)
                Spacer()
                NavigationLink {
                    BrowseChallengesView()
                } label: {
                    Text("Browse")
                        .font(.subheadline)
                }
            }

            if activeParticipations.isEmpty, completedParticipations.isEmpty {
                challengesEmptyState
            } else {
                if !activeParticipations.isEmpty {
                    ForEach(activeParticipations) { participation in
                        NavigationLink {
                            ChallengeDetailView(participation: participation)
                        } label: {
                            ChallengeProgressCard(participation: participation)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !completedParticipations.isEmpty {
                    DisclosureGroup("Completed (\(completedParticipations.count))") {
                        ForEach(completedParticipations) { participation in
                            NavigationLink {
                                ChallengeDetailView(participation: participation)
                            } label: {
                                CompletedChallengeCard(participation: participation)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
    }

    private var challengesEmptyState: some View {
        VStack(spacing: 8) {
            Text("No active challenges")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            NavigationLink {
                BrowseChallengesView()
            } label: {
                Text("Browse Challenges")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: - Activity Feed Section

    private var activityFeedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity")
                .font(.headline)

            FilterBar(selectedFilter: $selectedFilter, clubs: clubs)

            if filteredActivityItems.isEmpty {
                activityEmptyState
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(filteredActivityItems) { item in
                        ActivityItemRow(
                            item: item,
                            onShare: { shareActivity(item) },
                            onCallsignTap: { callsign in
                                navigateToProfile(callsign: callsign)
                            }
                        )
                    }
                }
            }
        }
        .navigationDestination(isPresented: $showingFriendProfile) {
            if let callsign = selectedCallsign {
                FriendProfileView(
                    callsign: callsign,
                    friendship: friendshipFor(callsign: callsign)
                )
            }
        }
    }

    private func navigateToProfile(callsign: String) {
        selectedCallsign = callsign
        showingFriendProfile = true
    }

    private func friendshipFor(callsign: String) -> Friendship? {
        acceptedFriends.first { $0.friendCallsign.uppercased() == callsign.uppercased() }
    }

    private var activityEmptyState: some View {
        ContentUnavailableView(
            "No Activity Yet",
            systemImage: "person.2",
            description: Text("Activity from friends and clubs will appear here.")
        )
        .padding(.vertical, 24)
    }

    private func shareActivity(_ item: ActivityItem) {
        itemToShare = item
        showingShareSheet = true
    }
}

// MARK: - ActivityView+Actions

extension ActivityView {
    func refresh() async {
        guard let syncService else {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            try await syncService.refreshChallenges(forceUpdate: true)
            for participation in activeParticipations {
                syncService.progressEngine.reevaluateAllQSOs(for: participation)
            }
            try modelContext.save()

            // Sync activity feed from server
            if let feedService = feedSyncService {
                try await feedService.syncFeed(sourceURL: "https://challenges.example.com")
            }
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    func handleInviteNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let source = userInfo["source"] as? String,
              let challengeId = userInfo["challengeId"] as? UUID
        else {
            return
        }

        let token = userInfo["token"] as? String

        pendingInvite = PendingChallengeInvite(
            sourceURL: source,
            challengeId: challengeId,
            token: token
        )
        showingInviteSheet = true
    }

    func evaluateNewQSOs() async {
        guard let syncService else {
            return
        }

        let descriptor = FetchDescriptor<QSO>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        do {
            let recentQSOs = try modelContext.fetch(descriptor)
            for qso in recentQSOs.prefix(100) {
                syncService.progressEngine.evaluateQSO(qso, notificationsEnabled: false)
            }
            try modelContext.save()
        } catch {
            // Silently fail - background operation
        }
    }

    func handleFriendInviteNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let token = userInfo["token"] as? String
        else {
            return
        }

        pendingFriendInviteToken = token
        showingFriendInviteSheet = true
    }

    func acceptFriendInvite() {
        guard let token = pendingFriendInviteToken,
              let service = friendsSyncService
        else {
            return
        }

        isProcessingFriendInvite = true

        Task {
            do {
                try await service.sendFriendRequestWithInvite(
                    inviteToken: token,
                    sourceURL: "https://challenges.example.com"
                )
                showingFriendInviteSheet = false
                pendingFriendInviteToken = nil
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
            isProcessingFriendInvite = false
        }
    }
}

// MARK: - FriendInviteConfirmSheet

private struct FriendInviteConfirmSheet: View {
    let token: String
    @Binding var isProcessing: Bool
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "person.badge.plus")
                    .font(.system(size: 60))
                    .foregroundStyle(.accent)

                Text("Friend Invite")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Someone has invited you to connect on Carrier Wave. Accept to send them a friend request.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        onAccept()
                    } label: {
                        if isProcessing {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Accept Invite")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isProcessing)

                    Button("Cancel", role: .cancel) {
                        onDismiss()
                    }
                    .disabled(isProcessing)
                }
                .padding()
            }
            .navigationTitle("Friend Invite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                        .disabled(isProcessing)
                }
            }
        }
        .presentationDetents([.medium])
    }

#Preview {
    ActivityView(tourState: TourState())
        .modelContainer(
            for: [
                ChallengeSource.self,
                ChallengeDefinition.self,
                ChallengeParticipation.self,
                ActivityItem.self,
                Club.self,
                Friendship.self,
            ], inMemory: true
        )
}

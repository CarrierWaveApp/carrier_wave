import SwiftData
import SwiftUI
import UIKit

// MARK: - ActivityView

struct ActivityView: View {
    let tourState: TourState

    /// When true, the view is already inside a navigation context
    var isInNavigationContext: Bool = false

    @Environment(\.modelContext) var modelContext
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    // MARK: - State (internal for extension access)

    @AppStorage("activityDedupCompleted") var dedupCompleted = false
    @State var isRefreshing = false

    @Query(sort: \ChallengeParticipation.joinedAt, order: .reverse)
    var allParticipations: [ChallengeParticipation]

    @State var allActivityItems: [ActivityItem] = []

    @Query var clubs: [Club]

    @Query(filter: #Predicate<Friendship> { $0.statusRawValue == "accepted" })
    var acceptedFriends: [Friendship]

    @Query(
        filter: #Predicate<Friendship> { $0.statusRawValue == "pending" && $0.isOutgoing == false }
    )
    var incomingRequests: [Friendship]

    @State var selectedFilter: FeedFilter = .all

    @State var syncService: ActivitiesSyncService?
    @State var friendsSyncService: FriendsSyncService?
    @State var clubsSyncService: ClubsSyncService?
    @State var feedSyncService: ActivityFeedSyncService?
    @State var errorMessage: String?
    @State var showingError = false

    // Invite handling
    @State var pendingInvite: PendingChallengeInvite?
    @State var showingInviteSheet = false
    @State var isJoiningFromInvite = false

    // Sharing
    @State var itemToShare: ActivityItem?
    @State var showingShareSheet = false
    @State var showingSummarySheet = false

    // Friend profile navigation
    @State var selectedCallsign: String?
    @State var showingFriendProfile = false
    @State var showingOwnProfile = false

    // Friend invite handling
    @State var pendingFriendInviteToken: String?
    @State var showingFriendInviteSheet = false
    @State var isProcessingFriendInvite = false

    // Community features prompt for existing users
    @AppStorage("activitiesServerPromptShown") var communityPromptShown = false
    @State var showingCommunityPrompt = false

    var activeParticipations: [ChallengeParticipation] {
        allParticipations.filter { $0.status == .active }
    }

    var completedParticipations: [ChallengeParticipation] {
        allParticipations.filter { $0.status == .completed }
    }

    var currentCallsign: String {
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

    var filteredActivityItems: [ActivityItem] {
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

    var body: some View {
        if isInNavigationContext {
            activityContent
        } else {
            NavigationStack {
                activityContent
            }
        }
    }

    var activityContent: some View {
        ScrollView {
            if horizontalSizeClass == .regular {
                // iPad: Side-by-side layout
                VStack(spacing: 16) {
                    friendRequestsBanner
                    HStack(alignment: .top, spacing: 24) {
                        challengesSection
                            .frame(minWidth: 300, idealWidth: 350, maxWidth: 400)
                        activityFeedSection
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding()
            } else {
                // iPhone: Vertical stack
                VStack(spacing: 24) {
                    friendRequestsBanner
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
                        .overlay(alignment: .topTrailing) {
                            if !incomingRequests.isEmpty {
                                Text("\(incomingRequests.count)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.red)
                                    .clipShape(Capsule())
                                    .offset(x: 8, y: -8)
                            }
                        }
                }
                .accessibilityLabel(
                    incomingRequests.isEmpty
                        ? "Friends"
                        : "Friends, \(incomingRequests.count) pending requests"
                )

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
                syncService = ActivitiesSyncService(modelContext: modelContext)
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
        .sheet(isPresented: $showingCommunityPrompt) {
            CommunityFeaturesPromptSheet(
                callsign: currentCallsign,
                onComplete: {
                    communityPromptShown = true
                    showingCommunityPrompt = false
                }
            )
        }
        .task {
            loadActivityItems()
            // Sync friends and pending requests from server
            await syncFriendsQuietly()
            // One-time cleanup of duplicate activities (after UI is shown)
            await deduplicateActivitiesIfNeeded()
            // Show community features prompt for existing users who haven't been asked
            if !communityPromptShown {
                communityPromptShown = true
                showingCommunityPrompt = true
            }
        }
        .task(id: "feedRefresh") {
            // Periodically refresh feed while tab is visible (cancelled on disappear)
            await periodicFeedRefresh()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .didDetectActivities)
        ) { _ in
            // Reload local activity items when new activities are detected
            loadActivityItems()
        }
        .miniTour(.challenges, tourState: tourState)
    }
}

// MARK: - ActivityView+Actions

extension ActivityView {
    func loadActivityItems() {
        var descriptor = FetchDescriptor<ActivityItem>(
            sortBy: [SortDescriptor(\ActivityItem.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 200
        allActivityItems = (try? modelContext.fetch(descriptor)) ?? []
    }

    func deduplicateActivitiesIfNeeded() async {
        guard !dedupCompleted else {
            return
        }

        let container = modelContext.container
        let callsign = currentCallsign

        // Run dedup on background thread with its own ModelContext
        await Task.detached {
            let context = ModelContext(container)
            context.autosaveEnabled = false

            let descriptor = FetchDescriptor<ActivityItem>(
                predicate: #Predicate { $0.isOwn && $0.callsign == callsign },
                sortBy: [SortDescriptor(\ActivityItem.timestamp, order: .forward)]
            )
            guard let items = try? context.fetch(descriptor), items.count > 1 else {
                return
            }

            var seen: [String: Bool] = [:]
            var deletedAny = false

            for item in items {
                let key = ActivityDetector.dedupKeyForItem(item)
                if seen[key] != nil {
                    context.delete(item)
                    deletedAny = true
                } else {
                    seen[key] = true
                }
            }

            if deletedAny {
                try? context.save()
            }
        }.value

        dedupCompleted = true
        // Reload to reflect any deletions
        loadActivityItems()
    }

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

            // Sync friends and pending requests from server
            await syncFriendsQuietly()

            // Sync activity feed from server
            if let feedService = feedSyncService {
                try await feedService.syncFeed(sourceURL: "https://activities.carrierwave.app")
            }

            // Reload activity items to pick up new feed items
            loadActivityItems()
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

        var descriptor = FetchDescriptor<QSO>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 100

        do {
            let recentQSOs = try modelContext.fetch(descriptor)
            for qso in recentQSOs {
                syncService.progressEngine.evaluateQSO(qso, notificationsEnabled: false)
            }
            try modelContext.save()
        } catch {
            // Silently fail - background operation
        }
    }

    /// Periodically refresh the activity feed while the tab is visible.
    /// Uses cooperative cancellation — SwiftUI cancels this task on disappear.
    func periodicFeedRefresh() async {
        // Wait 60 seconds before first refresh (initial load already happened)
        try? await Task.sleep(for: .seconds(60))

        while !Task.isCancelled {
            if let feedService = feedSyncService {
                try? await feedService.syncFeed(
                    sourceURL: "https://activities.carrierwave.app"
                )
                loadActivityItems()
            }
            try? await Task.sleep(for: .seconds(60))
        }
    }

    func syncFriendsQuietly() async {
        if friendsSyncService == nil {
            friendsSyncService = FriendsSyncService(modelContext: modelContext)
        }
        guard let service = friendsSyncService else {
            return
        }
        do {
            try await service.syncFriends(sourceURL: "https://activities.carrierwave.app")
        } catch {
            // Non-critical — don't show error for background friend sync
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
                    sourceURL: "https://activities.carrierwave.app"
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

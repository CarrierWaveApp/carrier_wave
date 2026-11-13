import CarrierWaveCore
import CarrierWaveData
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

    @State var allActivityItems: [ActivityItem] = []

    var sync = ClubsSyncService.shared
    var friends = FriendsSyncService.shared

    @State var selectedFilter: FeedFilter = .all

    @State var friendsSyncService: FriendsSyncService?
    @State var feedSyncService: ActivityFeedSyncService?
    @State var errorMessage: String?
    @State var showingError = false

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

    var acceptedFriends: [Friendship] {
        FriendsSyncService.shared.acceptedFriends
    }

    var incomingRequests: [Friendship] {
        FriendsSyncService.shared.incomingRequests
    }

    var clubs: [FfiClub] {
        sync.clubs
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
        case .club:
            return allActivityItems
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
            VStack(spacing: 24) {
                communitySection
                activityFeedSection
            }
            .padding()
        }
        .navigationTitle("Friends")
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
                .accessibilityLabel("Refresh")
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
            CallsignHistoryView(callsign: currentCallsign)
        }
        .onAppear {
            if friendsSyncService == nil {
                friendsSyncService = FriendsSyncService.shared
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
        .sheet(isPresented: $showingShareSheet) {
            if let item = itemToShare {
                ShareSheetView(item: item)
            }
        }
        .sheet(isPresented: $showingSummarySheet) {
            SummaryCardSheet(callsign: currentCallsign)
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
            // Sync feed from server immediately (don't wait for periodic refresh)
            await syncFeedQuietly()
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
    }
}

// MARK: - ActivityView+Actions

extension ActivityView {
    func loadActivityItems() {
        var descriptor = FetchDescriptor<ActivityItem>(
            predicate: #Predicate { !$0.isHidden },
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
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            // Sync friends and pending requests from server
            await syncFriendsQuietly()

            // Sync activity feed from server
            if let feedService = feedSyncService {
                try await feedService.syncFeed(sourceURL: ActivitiesClient.resolvedBaseURL)
            }

            // Reload activity items to pick up new feed items
            loadActivityItems()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

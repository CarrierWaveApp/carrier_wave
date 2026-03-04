import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - FriendsListView

struct FriendsListView: View {
    // MARK: Internal

    var body: some View {
        List {
            if !searchText.isEmpty {
                searchResultsSection
            } else {
                friendsContent
            }
        }
        .navigationTitle("Friends")
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search by callsign to add friends"
        )
        .onChange(of: searchText) { _, newValue in
            searchTask?.cancel()
            guard !newValue.isEmpty else {
                searchResults = []
                return
            }
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else {
                    return
                }
                await performSearch()
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { generateInviteLink() } label: {
                    Image(systemName: "link.badge.plus")
                }
                .accessibilityLabel("Invite Friend via Link")
            }
        }
        .onAppear {
            if friendsSyncService == nil {
                friendsSyncService = FriendsSyncService(modelContext: modelContext)
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
        .sheet(isPresented: $showingInviteSheet) {
            InviteLinkSheet(
                inviteLink: inviteLink,
                isGenerating: isGeneratingInvite,
                errorMessage: inviteLinkError,
                onDismiss: { showingInviteSheet = false }
            )
        }
        .task {
            await syncFriendsOnAppear()
            await loadSuggestions()
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Friendship.friendCallsign)
    private var friendships: [Friendship]

    @State private var friendsSyncService: FriendsSyncService?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingError = false

    // Inline search state
    @State private var searchText = ""
    @State private var searchResults: [UserSearchResult] = []
    @State private var isSearching = false
    @State private var sentRequests: Set<String> = []
    @State private var searchTask: Task<Void, Never>?

    // Invite link state
    @State private var showingInviteSheet = false
    @State private var isGeneratingInvite = false
    @State private var inviteLink: InviteLinkDTO?
    @State private var inviteLinkError: String?

    // Friend suggestions state
    @State private var suggestions: [FriendSuggestion] = []
    @State private var isLoadingSuggestions = false

    private let sourceURL = "https://activities.carrierwave.app"

    private var acceptedFriends: [Friendship] {
        friendships.filter(\.isAccepted)
    }

    private var incomingRequests: [Friendship] {
        friendships.filter { $0.isPending && !$0.isOutgoing }
    }

    private var outgoingRequests: [Friendship] {
        friendships.filter { $0.isPending && $0.isOutgoing }
    }

    // MARK: - Search Results

    @ViewBuilder
    private var searchResultsSection: some View {
        if isSearching {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .listRowBackground(Color.clear)
        } else if searchText.count >= 2, searchResults.isEmpty {
            ContentUnavailableView(
                "No Results",
                systemImage: "person.slash",
                description: Text("No users found matching \"\(searchText)\"")
            )
            .listRowBackground(Color.clear)
        } else if searchText.count < 2 {
            ContentUnavailableView(
                "Keep Typing",
                systemImage: "character.cursor.ibeam",
                description: Text("Enter at least 2 characters to search")
            )
            .listRowBackground(Color.clear)
        } else {
            Section("Search Results") {
                ForEach(searchResults, id: \.userId) { user in
                    SearchResultRow(
                        user: user,
                        isSent: sentRequests.contains(user.userId),
                        onSend: { sendRequest(to: user) }
                    )
                }
            }
        }
    }

    // MARK: - Friends Content

    @ViewBuilder
    private var friendsContent: some View {
        if !suggestions.isEmpty {
            FriendSuggestionsSection(
                suggestions: suggestions,
                onAdd: { addSuggestedFriend($0) },
                onDismiss: { dismissSuggestion($0) }
            )
        }

        if !incomingRequests.isEmpty {
            Section("Pending Requests") {
                ForEach(incomingRequests) { friendship in
                    IncomingRequestRow(
                        friendship: friendship,
                        onAccept: { acceptRequest(friendship) },
                        onDecline: { declineRequest(friendship) }
                    )
                }
            }
        }

        if !outgoingRequests.isEmpty {
            Section("Sent Requests") {
                ForEach(outgoingRequests) { friendship in
                    OutgoingRequestRow(friendship: friendship)
                }
            }
        }

        if !acceptedFriends.isEmpty {
            Section("Friends") {
                ForEach(acceptedFriends) { friendship in
                    NavigationLink {
                        FriendProfileView(
                            callsign: friendship.friendCallsign,
                            friendship: friendship
                        )
                    } label: {
                        FriendRow(friendship: friendship)
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        removeFriend(acceptedFriends[index])
                    }
                }
            }
        }

        if friendships.isEmpty, suggestions.isEmpty {
            ContentUnavailableView(
                "No Friends Yet",
                systemImage: "person.2",
                description: Text("Type a callsign above to find and add friends")
            )
            .listRowBackground(Color.clear)
        }
    }
}

// MARK: - FriendsListView+Search

private extension FriendsListView {
    func performSearch() async {
        guard searchText.count >= 2, let service = friendsSyncService else {
            searchResults = []
            return
        }

        isSearching = true
        defer { isSearching = false }

        do {
            searchResults = try await service.searchUsers(
                query: searchText, sourceURL: sourceURL
            )
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
            searchResults = []
        }
    }

    func sendRequest(to user: UserSearchResult) {
        guard let service = friendsSyncService else {
            return
        }
        sentRequests.insert(user.userId)

        Task {
            do {
                try await service.sendFriendRequest(
                    toUserId: user.userId, sourceURL: sourceURL
                )
            } catch {
                sentRequests.remove(user.userId)
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
}

// MARK: - FriendsListView+Actions

private extension FriendsListView {
    func acceptRequest(_ friendship: Friendship) {
        guard let service = friendsSyncService else {
            return
        }
        Task {
            do {
                try await service.acceptFriendRequest(
                    friendship, sourceURL: sourceURL
                )
            } catch {
                // Re-sync to clean up stale local data
                try? await service.syncFriends(sourceURL: sourceURL)
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    func declineRequest(_ friendship: Friendship) {
        guard let service = friendsSyncService else {
            return
        }
        Task {
            do {
                try await service.declineFriendRequest(
                    friendship, sourceURL: sourceURL
                )
            } catch {
                // Re-sync to clean up stale local data
                try? await service.syncFriends(sourceURL: sourceURL)
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    func removeFriend(_ friendship: Friendship) {
        guard let service = friendsSyncService else {
            return
        }
        Task {
            do {
                try await service.removeFriend(friendship, sourceURL: sourceURL)
            } catch {
                // Re-sync to clean up stale local data
                try? await service.syncFriends(sourceURL: sourceURL)
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    func syncFriendsOnAppear() async {
        if friendsSyncService == nil {
            friendsSyncService = FriendsSyncService(modelContext: modelContext)
        }
        guard let service = friendsSyncService else {
            return
        }
        do {
            try await service.syncFriends(sourceURL: sourceURL)
        } catch {
            // Non-critical — @Query still shows locally cached friendships
        }
    }

    func loadSuggestions() async {
        if friendsSyncService == nil {
            friendsSyncService = FriendsSyncService(modelContext: modelContext)
        }
        guard let service = friendsSyncService else {
            return
        }

        isLoadingSuggestions = true
        defer { isLoadingSuggestions = false }

        do {
            suggestions = try await service.computeSuggestions(
                container: modelContext.container,
                sourceURL: sourceURL
            )
        } catch {
            // Silently fail — suggestions are non-critical
        }
    }

    func addSuggestedFriend(_ suggestion: FriendSuggestion) {
        guard let service = friendsSyncService else {
            return
        }
        Task {
            do {
                try await service.sendFriendRequest(
                    toUserId: suggestion.userId,
                    sourceURL: sourceURL
                )
                suggestions.removeAll { $0.callsign == suggestion.callsign }
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    func dismissSuggestion(_ suggestion: FriendSuggestion) {
        guard let service = friendsSyncService else {
            return
        }
        do {
            try service.dismissSuggestion(callsign: suggestion.callsign)
            suggestions.removeAll { $0.callsign == suggestion.callsign }
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    func generateInviteLink() {
        if friendsSyncService == nil {
            friendsSyncService = FriendsSyncService(modelContext: modelContext)
        }
        guard let service = friendsSyncService else {
            return
        }

        inviteLink = nil
        inviteLinkError = nil
        isGeneratingInvite = true
        showingInviteSheet = true

        Task {
            do {
                inviteLink = try await service.generateInviteLink(
                    sourceURL: sourceURL
                )
            } catch {
                inviteLinkError = error.localizedDescription
            }
            isGeneratingInvite = false
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        FriendsListView()
    }
    .modelContainer(for: [Friendship.self, DismissedSuggestion.self], inMemory: true)
}

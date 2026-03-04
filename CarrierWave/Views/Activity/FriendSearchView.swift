import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - FriendSearchView

struct FriendSearchView: View {
    // MARK: Internal

    var body: some View {
        List {
            if isSearching {
                HStack {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(.circular)
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
            } else if searchText.count < 2, searchText.isEmpty == false {
                ContentUnavailableView(
                    "Keep Typing",
                    systemImage: "character.cursor.ibeam",
                    description: Text("Enter at least 2 characters to search")
                )
                .listRowBackground(Color.clear)
            } else if searchText.isEmpty {
                ContentUnavailableView(
                    "Search for Friends",
                    systemImage: "magnifyingglass",
                    description: Text("Search by callsign or display name")
                )
                .listRowBackground(Color.clear)
            } else {
                searchResultsList
            }
        }
        .navigationTitle("Add Friend")
        .searchable(text: $searchText, prompt: "Search by callsign")
        .onChange(of: searchText) { _, _ in
            searchTask?.cancel()
            searchTask = Task {
                // Debounce: wait 300ms before searching
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else {
                    return
                }
                await performSearch()
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
        .onAppear {
            if friendsSyncService == nil {
                friendsSyncService = FriendsSyncService(modelContext: modelContext)
            }
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext
    @State private var friendsSyncService: FriendsSyncService?

    @State private var searchText = ""
    @State private var searchResults: [UserSearchResult] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var sentRequests: Set<String> = []
    @State private var searchTask: Task<Void, Never>?

    private let sourceURL = "https://activities.carrierwave.app"

    private var searchResultsList: some View {
        ForEach(searchResults, id: \.userId) { user in
            SearchResultRow(
                user: user,
                isSent: sentRequests.contains(user.userId),
                onSend: {
                    sendRequest(to: user)
                }
            )
        }
    }

    private func performSearch() async {
        guard searchText.count >= 2 else {
            searchResults = []
            return
        }

        guard let service = friendsSyncService else {
            return
        }

        isSearching = true
        defer { isSearching = false }

        do {
            searchResults = try await service.searchUsers(query: searchText, sourceURL: sourceURL)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
            searchResults = []
        }
    }

    private func sendRequest(to user: UserSearchResult) {
        guard let service = friendsSyncService else {
            return
        }
        sentRequests.insert(user.userId)

        Task {
            do {
                try await service.sendFriendRequest(toUserId: user.userId, sourceURL: sourceURL)
            } catch {
                // Remove from sent if failed
                sentRequests.remove(user.userId)
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
}

// MARK: - SearchResultRow

struct SearchResultRow: View {
    let user: UserSearchResult
    let isSent: Bool
    let onSend: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(user.callsign)
                    .font(.headline)
                if let displayName = user.displayName {
                    Text(displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isSent {
                Text("Sent")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Button("Add") {
                    onSend()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        FriendSearchView()
    }
}

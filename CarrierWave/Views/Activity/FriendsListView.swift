import SwiftData
import SwiftUI

// MARK: - FriendsListView

struct FriendsListView: View {
    // MARK: Internal

    var body: some View {
        Group {
            if friendships.isEmpty {
                ContentUnavailableView(
                    "No Friends Yet",
                    systemImage: "person.2",
                    description: Text(
                        "Search for friends by their callsign to connect and see their activity"
                    )
                )
            } else {
                friendsList
            }
        }
        .navigationTitle("Friends")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    FriendSearchView()
                } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    generateInviteLink()
                } label: {
                    Label("Invite Friend", systemImage: "link.badge.plus")
                }
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
                onDismiss: { showingInviteSheet = false }
            )
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

    // Invite link state
    @State private var showingInviteSheet = false
    @State private var isGeneratingInvite = false
    @State private var inviteLink: InviteLinkDTO?

    /// For now, hardcode the source URL (will come from settings later)
    private let sourceURL = "https://challenges.example.com"

    private var acceptedFriends: [Friendship] {
        friendships.filter(\.isAccepted)
    }

    private var incomingRequests: [Friendship] {
        friendships.filter { $0.isPending && !$0.isOutgoing }
    }

    private var outgoingRequests: [Friendship] {
        friendships.filter { $0.isPending && $0.isOutgoing }
    }

    private var friendsList: some View {
        List {
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
                                callsign: friendship.friendCallsign, friendship: friendship
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
        }
    }

    private func acceptRequest(_ friendship: Friendship) {
        guard let service = friendsSyncService else {
            return
        }
        Task {
            do {
                try await service.acceptFriendRequest(friendship, sourceURL: sourceURL)
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    private func declineRequest(_ friendship: Friendship) {
        guard let service = friendsSyncService else {
            return
        }
        Task {
            do {
                try await service.declineFriendRequest(friendship, sourceURL: sourceURL)
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    private func removeFriend(_ friendship: Friendship) {
        guard let service = friendsSyncService else {
            return
        }
        Task {
            do {
                try await service.removeFriend(friendship, sourceURL: sourceURL)
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    private func generateInviteLink() {
        guard let service = friendsSyncService else {
            return
        }

        inviteLink = nil
        isGeneratingInvite = true
        showingInviteSheet = true

        Task {
            do {
                inviteLink = try await service.generateInviteLink(sourceURL: sourceURL)
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
                showingInviteSheet = false
            }
            isGeneratingInvite = false
        }
    }
}

// MARK: - IncomingRequestRow

private struct IncomingRequestRow: View {
    let friendship: Friendship
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        HStack {
            Text(friendship.friendCallsign)
                .font(.headline)

            Spacer()

            Button("Accept") {
                onAccept()
            }
            .buttonStyle(.borderedProminent)

            Button("Decline") {
                onDecline()
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
    }
}

// MARK: - OutgoingRequestRow

private struct OutgoingRequestRow: View {
    let friendship: Friendship

    var body: some View {
        HStack {
            Text(friendship.friendCallsign)
                .font(.headline)

            Spacer()

            Text("Pending...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - FriendRow

private struct FriendRow: View {
    let friendship: Friendship

    var body: some View {
        HStack {
            Text(friendship.friendCallsign)
                .font(.headline)

            Spacer()

            if let acceptedAt = friendship.acceptedAt {
                Text(acceptedAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - InviteLinkSheet

private struct InviteLinkSheet: View {
    // MARK: Internal

    let inviteLink: InviteLinkDTO?
    let isGenerating: Bool
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if isGenerating {
                    ProgressView("Generating invite link...")
                        .frame(maxHeight: .infinity)
                } else if let invite = inviteLink {
                    inviteContent(invite)
                } else {
                    ContentUnavailableView(
                        "Unable to Generate Link",
                        systemImage: "exclamationmark.triangle",
                        description: Text("Please try again later.")
                    )
                }
            }
            .padding()
            .navigationTitle("Invite Friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onDismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: Private

    private func inviteContent(_ invite: InviteLinkDTO) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.tint)

            Text("Share this link with a friend")
                .font(.headline)

            Text(
                "When they tap the link, they'll be able to send you a friend request in Carrier Wave."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            Text(invite.url)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            if invite.expiresAt > Date() {
                Text("Expires \(invite.expiresAt, style: .relative)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            ShareLink(item: URL(string: invite.url)!) {
                Label("Share Link", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                UIPasteboard.general.string = invite.url
            } label: {
                Label("Copy to Clipboard", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        FriendsListView()
    }
    .modelContainer(for: [Friendship.self], inMemory: true)
}

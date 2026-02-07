import Combine
import Foundation
import SwiftData

// MARK: - FriendsSyncService

@MainActor
final class FriendsSyncService: ObservableObject {
    // MARK: Lifecycle

    init(modelContext: ModelContext, client: ActivitiesClient? = nil) {
        self.modelContext = modelContext
        self.client = client ?? ActivitiesClient()
    }

    // MARK: Internal

    @Published var isSyncing = false
    @Published var syncError: String?

    let modelContext: ModelContext
    let client: ActivitiesClient

    // MARK: - Sync

    /// Sync friends and pending requests from server
    func syncFriends(sourceURL: String) async throws {
        guard let authToken = try? client.getAuthToken() else {
            throw FriendsSyncError.notAuthenticated
        }

        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        // Fetch friends from server
        let friends = try await client.getFriends(sourceURL: sourceURL, authToken: authToken)
        let pending = try await client.getPendingRequests(
            sourceURL: sourceURL, authToken: authToken
        )

        // Update local models
        try updateLocalFriendships(friends: friends, pending: pending)
    }

    // MARK: - Search

    /// Search for users by callsign
    func searchUsers(query: String, sourceURL: String) async throws -> [UserSearchResult] {
        try await client.searchUsers(query: query, sourceURL: sourceURL)
    }

    // MARK: - Friend Request Actions

    /// Send a friend request
    func sendFriendRequest(toUserId: String, sourceURL: String) async throws {
        guard let authToken = try? client.getAuthToken() else {
            throw FriendsSyncError.notAuthenticated
        }

        let request = try await client.sendFriendRequest(
            toUserId: toUserId,
            sourceURL: sourceURL,
            authToken: authToken
        )

        // Create local pending friendship
        let friendship = Friendship(
            friendCallsign: request.toCallsign,
            friendUserId: request.toUserId,
            status: .pending,
            requestedAt: request.requestedAt,
            isOutgoing: true
        )
        modelContext.insert(friendship)
        try modelContext.save()
    }

    /// Accept a friend request
    func acceptFriendRequest(_ friendship: Friendship, sourceURL: String) async throws {
        guard let authToken = try? client.getAuthToken() else {
            throw FriendsSyncError.notAuthenticated
        }

        // Need the server request ID - for now we use friendship.id
        // In real implementation, we'd store the server request ID
        try await client.acceptFriendRequest(
            requestId: friendship.id,
            sourceURL: sourceURL,
            authToken: authToken
        )

        friendship.status = .accepted
        friendship.acceptedAt = Date()
        try modelContext.save()
    }

    /// Decline a friend request
    func declineFriendRequest(_ friendship: Friendship, sourceURL: String) async throws {
        guard let authToken = try? client.getAuthToken() else {
            throw FriendsSyncError.notAuthenticated
        }

        try await client.declineFriendRequest(
            requestId: friendship.id,
            sourceURL: sourceURL,
            authToken: authToken
        )

        modelContext.delete(friendship)
        try modelContext.save()
    }

    /// Remove a friend
    func removeFriend(_ friendship: Friendship, sourceURL: String) async throws {
        guard let authToken = try? client.getAuthToken() else {
            throw FriendsSyncError.notAuthenticated
        }

        try await client.removeFriend(
            friendshipId: friendship.id,
            sourceURL: sourceURL,
            authToken: authToken
        )

        modelContext.delete(friendship)
        try modelContext.save()
    }

    // MARK: - Invite Links

    /// Generate a shareable invite link
    func generateInviteLink(sourceURL: String) async throws -> InviteLinkDTO {
        guard let authToken = try? client.getAuthToken() else {
            throw FriendsSyncError.notAuthenticated
        }

        return try await client.generateInviteLink(sourceURL: sourceURL, authToken: authToken)
    }

    /// Send a friend request using an invite token
    func sendFriendRequestWithInvite(inviteToken: String, sourceURL: String) async throws {
        guard let authToken = try? client.getAuthToken() else {
            throw FriendsSyncError.notAuthenticated
        }

        let request = try await client.sendFriendRequestWithInvite(
            inviteToken: inviteToken,
            sourceURL: sourceURL,
            authToken: authToken
        )

        // Create local pending friendship
        let friendship = Friendship(
            friendCallsign: request.toCallsign,
            friendUserId: request.toUserId,
            status: .pending,
            requestedAt: request.requestedAt,
            isOutgoing: true
        )
        modelContext.insert(friendship)
        try modelContext.save()
    }

    // MARK: - Friend Suggestions

    /// Compute friend suggestions: callsigns with 3+ QSOs that are registered app users.
    func computeSuggestions(
        container: ModelContainer,
        sourceURL: String
    ) async throws -> [FriendSuggestion] {
        guard let authToken = try? client.getAuthToken() else {
            return []
        }

        // 1. Count QSOs per callsign on background actor
        let ownCallsigns = collectOwnCallsigns()
        let actor = FriendSuggestionActor()
        let callsignCounts = try await actor.computeCallsignCounts(
            container: container,
            ownCallsigns: ownCallsigns
        )

        if callsignCounts.isEmpty {
            return []
        }

        // 2. Filter out dismissed and existing friends/pending
        let excludedCallsigns = try collectExcludedCallsigns()
        let candidates = callsignCounts.filter {
            !excludedCallsigns.contains($0.callsign.uppercased())
        }

        if candidates.isEmpty {
            return []
        }

        // 3. Validate against server (which are registered users?)
        let candidateCallsigns = candidates.map(\.callsign)
        let validatedUsers = try await client.getSuggestions(
            callsigns: candidateCallsigns,
            sourceURL: sourceURL,
            authToken: authToken
        )

        // 4. Merge server user IDs with local QSO counts
        let countsByCallsign = Dictionary(
            uniqueKeysWithValues: candidates.map { ($0.callsign.uppercased(), $0.count) }
        )

        return validatedUsers.compactMap { dto in
            guard let count = countsByCallsign[dto.callsign.uppercased()] else {
                return nil
            }
            return FriendSuggestion(
                userId: dto.userId,
                callsign: dto.callsign,
                qsoCount: count
            )
        }.sorted { $0.qsoCount > $1.qsoCount }
    }

    /// Dismiss a friend suggestion so it doesn't reappear.
    func dismissSuggestion(callsign: String) throws {
        let dismissed = DismissedSuggestion(callsign: callsign)
        modelContext.insert(dismissed)
        try modelContext.save()
    }

    // MARK: Private

    /// Collect user's own callsigns to exclude from suggestions.
    private func collectOwnCallsigns() -> Set<String> {
        var callsigns = Set<String>()

        if let current = try? KeychainHelper.shared.readString(
            for: KeychainHelper.Keys.currentCallsign
        ), !current.isEmpty {
            callsigns.insert(current.uppercased())
        }

        return callsigns
    }

    /// Collect callsigns to exclude: dismissed, already friends, and pending requests.
    private func collectExcludedCallsigns() throws -> Set<String> {
        var excluded = Set<String>()

        // Dismissed suggestions
        let dismissedDescriptor = FetchDescriptor<DismissedSuggestion>()
        let dismissed = (try? modelContext.fetch(dismissedDescriptor)) ?? []
        for item in dismissed {
            excluded.insert(item.callsign.uppercased())
        }

        // Existing friendships (accepted + pending)
        let friendDescriptor = FetchDescriptor<Friendship>()
        let friendships = (try? modelContext.fetch(friendDescriptor)) ?? []
        for item in friendships {
            excluded.insert(item.friendCallsign.uppercased())
        }

        return excluded
    }

    private func updateLocalFriendships(friends: [FriendDTO], pending: PendingRequestsDTO) throws {
        // Fetch existing local friendships
        let descriptor = FetchDescriptor<Friendship>()
        let existing = try modelContext.fetch(descriptor)
        let existingByUserId = Dictionary(
            uniqueKeysWithValues: existing.map { ($0.friendUserId, $0) }
        )

        var seenUserIds = Set<String>()

        // Update/create accepted friends
        updateAcceptedFriends(
            friends: friends, existingByUserId: existingByUserId, seenUserIds: &seenUserIds
        )

        // Update/create pending requests
        updatePendingRequests(
            pending: pending, existingByUserId: existingByUserId, seenUserIds: &seenUserIds
        )

        // Remove friendships no longer on server
        for local in existing where !seenUserIds.contains(local.friendUserId) {
            modelContext.delete(local)
        }

        try modelContext.save()
    }

    private func updateAcceptedFriends(
        friends: [FriendDTO],
        existingByUserId: [String: Friendship],
        seenUserIds: inout Set<String>
    ) {
        for friend in friends {
            seenUserIds.insert(friend.userId)
            if let local = existingByUserId[friend.userId] {
                local.status = .accepted
                local.acceptedAt = friend.acceptedAt
            } else {
                let friendship = Friendship(
                    id: friend.friendshipId,
                    friendCallsign: friend.callsign,
                    friendUserId: friend.userId,
                    status: .accepted,
                    acceptedAt: friend.acceptedAt,
                    isOutgoing: false
                )
                modelContext.insert(friendship)
            }
        }
    }

    private func updatePendingRequests(
        pending: PendingRequestsDTO,
        existingByUserId: [String: Friendship],
        seenUserIds: inout Set<String>
    ) {
        // Update/create incoming requests
        for request in pending.incoming {
            seenUserIds.insert(request.fromUserId)
            if let local = existingByUserId[request.fromUserId] {
                local.status = .pending
                local.isOutgoing = false
            } else {
                let friendship = Friendship(
                    id: request.id,
                    friendCallsign: request.fromCallsign,
                    friendUserId: request.fromUserId,
                    status: .pending,
                    requestedAt: request.requestedAt,
                    isOutgoing: false
                )
                modelContext.insert(friendship)
            }
        }

        // Update/create outgoing requests
        for request in pending.outgoing {
            seenUserIds.insert(request.toUserId)
            if let local = existingByUserId[request.toUserId] {
                local.status = .pending
                local.isOutgoing = true
            } else {
                let friendship = Friendship(
                    id: request.id,
                    friendCallsign: request.toCallsign,
                    friendUserId: request.toUserId,
                    status: .pending,
                    requestedAt: request.requestedAt,
                    isOutgoing: true
                )
                modelContext.insert(friendship)
            }
        }
    }
}

// MARK: - FriendsSyncError

enum FriendsSyncError: LocalizedError {
    case notAuthenticated
    case syncFailed(String)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "Please sign in to manage friends"
        case let .syncFailed(message):
            "Sync failed: \(message)"
        }
    }
}

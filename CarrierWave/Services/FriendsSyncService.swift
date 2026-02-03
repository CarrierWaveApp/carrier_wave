import Combine
import Foundation
import SwiftData

// MARK: - FriendsSyncService

@MainActor
final class FriendsSyncService: ObservableObject {
    // MARK: Lifecycle

    init(modelContext: ModelContext, client: ChallengesClient? = nil) {
        self.modelContext = modelContext
        self.client = client ?? ChallengesClient()
    }

    // MARK: Internal

    @Published var isSyncing = false
    @Published var syncError: String?

    let modelContext: ModelContext
    let client: ChallengesClient

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
        let pending = try await client.getPendingRequests(sourceURL: sourceURL, authToken: authToken)

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

    // MARK: Private

    private func updateLocalFriendships(friends: [FriendDTO], pending: PendingRequestsDTO) throws {
        // Fetch existing local friendships
        let descriptor = FetchDescriptor<Friendship>()
        let existing = try modelContext.fetch(descriptor)
        let existingByUserId = Dictionary(uniqueKeysWithValues: existing.map { ($0.friendUserId, $0) })

        var seenUserIds = Set<String>()

        // Update/create accepted friends
        updateAcceptedFriends(friends: friends, existingByUserId: existingByUserId, seenUserIds: &seenUserIds)

        // Update/create pending requests
        updatePendingRequests(pending: pending, existingByUserId: existingByUserId, seenUserIds: &seenUserIds)

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

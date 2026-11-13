import CarrierWaveCore
import CarrierWaveData
import Foundation
import OSLog
import SwiftData

// MARK: - FriendsFetch

/// Bounded fetch size for friendship reads (matches the Rust store's limit).
nonisolated private enum FriendsFetch {
    static let limit: Int64 = 1_000
}

// MARK: - FriendsSyncService

/// Friends are backed entirely by the shared Rust core: the encrypted `FieldStore`
/// holds the friendship cache, and `FriendsApi` (cw-net) does the
/// fetch→parse→store→reconcile sync plus all request actions. This `@MainActor`
/// singleton is the facade the SwiftUI layer talks to — it publishes the accepted
/// friends / incoming / outgoing lists and an O(1) accepted-callsign set the
/// logger/dashboard/spot rows use to flag friends on the air.
@Observable
@MainActor
final class FriendsSyncService {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    /// Shared singleton — call `configure()` from the app entry point.
    static let shared = FriendsSyncService()

    var isSyncing = false
    var syncError: String?

    /// Accepted friends (callsign-sorted). Drives the Friends list + dashboard.
    private(set) var acceptedFriends: [Friendship] = []
    /// Incoming pending requests (drives the Requests section + tab badge).
    private(set) var incomingRequests: [Friendship] = []
    /// Outgoing pending requests.
    private(set) var outgoingRequests: [Friendship] = []
    /// Uppercased accepted-friend callsigns for O(1) "is friend on air" checks.
    private(set) var acceptedFriendCallsigns: Set<String> = []
    /// Count of incoming pending requests (the Friends tab badge).
    private(set) var incomingRequestCount = 0

    // MARK: - Lookups

    /// All accepted + pending friendships (for callers that want the full set).
    var allFriendships: [Friendship] {
        acceptedFriends + incomingRequests + outgoingRequests
    }

    /// Configure the shared instance. Loads the cache from the Rust store on a
    /// background task so it never blocks the scene-update window.
    func configure() {
        Task { await reloadFromStore() }
    }

    /// Back-compat shim: the SwiftData container is no longer used (friends live
    /// in the Rust store). Kept so the single app-startup call site is unchanged.
    func configure(container _: ModelContainer) {
        configure()
    }

    /// True if the callsign is an accepted friend.
    func isFriend(callsign: String) -> Bool {
        acceptedFriendCallsigns.contains(callsign.uppercased())
    }

    // MARK: - Sync

    /// Sync friends + pending requests via the Rust `FriendsApi`, then reload the
    /// published lists from the store.
    func syncFriends(sourceURL _: String = "") async throws {
        let (bearer, api) = try await authedApi()
        isSyncing = true
        syncError = nil
        // Suspension while the apply's commit holds the cw-store SQLite lock is
        // a 0xdead10cc RunningBoard kill (same class as clubs sync).
        let suspensionGuard = BackgroundTaskAssertion(name: "FriendsSyncService.syncFriends")
        defer {
            suspensionGuard.release()
            isSyncing = false
        }
        do {
            _ = try await api.syncFriends(bearer: bearer)
            await reloadFromStore()
        } catch {
            syncError = error.localizedDescription
            throw error
        }
    }

    // MARK: - Search

    func searchUsers(query: String, sourceURL _: String = "") async throws -> [UserSearchResult] {
        let (bearer, api) = try await authedApi()
        return try await api.searchUsers(bearer: bearer, query: query).map {
            UserSearchResult(userId: $0.userId, callsign: $0.callsign, displayName: $0.displayName)
        }
    }

    // MARK: - Friend Request Actions

    func sendFriendRequest(toUserId: String, sourceURL _: String = "") async throws {
        let (bearer, api) = try await authedApi()
        try await api.sendRequest(bearer: bearer, toUserId: toUserId)
        try? await syncFriends()
    }

    func acceptFriendRequest(_ friendship: Friendship, sourceURL _: String = "") async throws {
        guard let requestId = friendship.requestId else {
            return
        }
        let (bearer, api) = try await authedApi()
        try await api.acceptRequest(bearer: bearer, requestId: requestId)
        try? await syncFriends()
    }

    func declineFriendRequest(_ friendship: Friendship, sourceURL _: String = "") async throws {
        guard let requestId = friendship.requestId else {
            return
        }
        let (bearer, api) = try await authedApi()
        try await api.declineRequest(bearer: bearer, requestId: requestId)
        try? await syncFriends()
    }

    func removeFriend(_ friendship: Friendship, sourceURL _: String = "") async throws {
        guard let friendshipId = friendship.friendshipId else {
            return
        }
        let (bearer, api) = try await authedApi()
        try await api.removeFriend(bearer: bearer, friendshipId: friendshipId)
        try? await syncFriends()
    }

    // MARK: - Invite Links

    func generateInviteLink(sourceURL _: String = "") async throws -> InviteLinkDTO {
        let (bearer, api) = try await authedApi()
        let link = try await api.getInviteLink(bearer: bearer)
        return InviteLinkDTO(
            token: link.token,
            url: link.url,
            expiresAt: Date(timeIntervalSince1970: TimeInterval(link.expiresAt))
        )
    }

    func sendFriendRequestWithInvite(inviteToken: String, sourceURL _: String = "") async throws {
        let (bearer, api) = try await authedApi()
        try await api.sendRequestWithInvite(bearer: bearer, inviteToken: inviteToken)
        try? await syncFriends()
    }

    // MARK: - Friend Suggestions

    /// Compute friend suggestions: callsigns with 3+ QSOs that are registered app
    /// users (QSO counting stays local via `FriendSuggestionActor`; the registered
    /// check goes through the Rust `FriendsApi`).
    func computeSuggestions(
        container: ModelContainer,
        sourceURL _: String = ""
    ) async throws -> [FriendSuggestion] {
        let (bearer, api) = try await authedApi()

        let ownCallsigns = collectOwnCallsigns()
        let actor = FriendSuggestionActor()
        let callsignCounts = try await actor.computeCallsignCounts(
            container: container,
            ownCallsigns: ownCallsigns
        )
        if callsignCounts.isEmpty {
            return []
        }

        let excluded = collectExcludedCallsigns()
        let candidates = callsignCounts.filter { !excluded.contains($0.callsign.uppercased()) }
        if candidates.isEmpty {
            return []
        }

        let validated = try await api.getSuggestions(
            bearer: bearer,
            callsigns: candidates.map(\.callsign)
        )
        let countsByCallsign = Dictionary(
            candidates.map { ($0.callsign.uppercased(), $0.count) },
            uniquingKeysWith: { first, _ in first }
        )
        return validated.compactMap { suggestion in
            guard let count = countsByCallsign[suggestion.callsign.uppercased()] else {
                return nil
            }
            return FriendSuggestion(
                userId: suggestion.userId,
                callsign: suggestion.callsign,
                qsoCount: count
            )
        }.sorted { $0.qsoCount > $1.qsoCount }
    }

    /// Dismiss a friend suggestion so it doesn't reappear (local-only, in
    /// `UserDefaults` now that there's no SwiftData model).
    func dismissSuggestion(callsign: String) {
        var dismissed = dismissedSuggestions
        dismissed.insert(callsign.uppercased())
        UserDefaults.standard.set(Array(dismissed), forKey: Self.dismissedKey)
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "CarrierWave",
        category: "FriendsSync"
    )

    private static let dismissedKey = "dismissedFriendSuggestions"

    private var friendsApi: FriendsApi?
    private var client: ActivitiesClient?

    private var resolvedClient: ActivitiesClient {
        if let client {
            return client
        }
        let newClient = ActivitiesClient()
        client = newClient
        return newClient
    }

    private var dismissedSuggestions: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: Self.dismissedKey) ?? [])
    }

    /// Resolve a bearer token + lazily-built `FriendsApi`, throwing if unauthenticated.
    private func authedApi() async throws -> (bearer: String, api: FriendsApi) {
        guard let bearer = await resolvedClient.ensureAuthToken() else {
            throw FriendsSyncError.notAuthenticated
        }
        return try await (bearer, ensureApi())
    }

    private func ensureApi() async throws -> FriendsApi {
        if let friendsApi {
            return friendsApi
        }
        let store = try await CwStoreProvider.shared.store()
        let baseURL = ActivitiesClient.normalizeBase(ActivitiesClient.resolvedBaseURL)
        let api = try FriendsApi(store: store, baseUrl: baseURL)
        friendsApi = api
        return api
    }

    /// Read all friendships from the store (off-main) and rebuild the published lists.
    private func reloadFromStore() async {
        guard let store = try? await CwStoreProvider.shared.store() else {
            return
        }
        let rows = await Task.detached {
            (try? store.fetchFriendships(
                filter: FfiFriendshipFilter(status: nil),
                limit: FriendsFetch.limit,
                offset: 0
            )) ?? []
        }.value
        let friendships = rows.map(Friendship.init(ffi:))
        acceptedFriends = friendships.filter(\.isAccepted).sorted { $0.friendCallsign < $1.friendCallsign }
        let pending = friendships.filter(\.isPending)
        incomingRequests = pending.filter { !$0.isOutgoing }
        outgoingRequests = pending.filter(\.isOutgoing)
        acceptedFriendCallsigns = Set(acceptedFriends.map { $0.friendCallsign.uppercased() })
        incomingRequestCount = incomingRequests.count
    }

    /// The user's own callsigns, excluded from suggestions.
    private func collectOwnCallsigns() -> Set<String> {
        guard let current = try? KeychainHelper.shared.readString(
            for: KeychainHelper.Keys.currentCallsign
        ), !current.isEmpty else {
            return []
        }
        return [current.uppercased()]
    }

    /// Callsigns to exclude from suggestions: dismissed + already friends/pending.
    private func collectExcludedCallsigns() -> Set<String> {
        var excluded = dismissedSuggestions
        for friendship in allFriendships {
            excluded.insert(friendship.friendCallsign.uppercased())
        }
        return excluded
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

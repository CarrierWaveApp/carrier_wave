import CarrierWaveCore
import CarrierWaveData
import Foundation

// MARK: - FriendshipStatus

enum FriendshipStatus: String, Codable {
    case pending
    case accepted
    case declined
}

// MARK: - Friendship

/// A friendship or pending friend request, projected from the shared Rust store
/// (`FfiFriendship`). Formerly a SwiftData `@Model`; the social graph now lives
/// entirely in the Rust `FieldStore` and is synced by `FriendsApi`, so this is a
/// plain value type the SwiftUI layer renders. Identity is the other party's
/// user id (stable across re-syncs).
struct Friendship: Identifiable, Hashable {
    // MARK: Lifecycle

    init(
        friendCallsign: String,
        friendUserId: String,
        status: FriendshipStatus = .pending,
        requestedAt: Date = Date(),
        acceptedAt: Date? = nil,
        isOutgoing: Bool,
        requestId: String? = nil,
        friendshipId: String? = nil
    ) {
        self.friendCallsign = friendCallsign
        self.friendUserId = friendUserId
        self.status = status
        self.requestedAt = requestedAt
        self.acceptedAt = acceptedAt
        self.isOutgoing = isOutgoing
        self.requestId = requestId
        self.friendshipId = friendshipId
    }

    /// Build from the shared-store record.
    init(ffi: FfiFriendship) {
        friendCallsign = ffi.friendCallsign
        friendUserId = ffi.friendUserId
        status = FriendshipStatus(rawValue: ffi.status) ?? .pending
        requestedAt = Date(timeIntervalSince1970: TimeInterval(ffi.requestedAt))
        acceptedAt = ffi.acceptedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        isOutgoing = ffi.isOutgoing
        requestId = ffi.requestId
        friendshipId = ffi.friendshipId
    }

    // MARK: Internal

    var friendCallsign: String
    var friendUserId: String
    var status: FriendshipStatus
    var requestedAt: Date
    var acceptedAt: Date?
    var isOutgoing: Bool

    /// Server friend-request id (pending rows) — used to accept/decline.
    var requestId: String?
    /// Server friendship id (accepted rows) — used to remove.
    var friendshipId: String?

    /// Stable identity = the other party's user id.
    var id: String {
        friendUserId
    }

    var isAccepted: Bool {
        status == .accepted
    }

    var isPending: Bool {
        status == .pending
    }
}

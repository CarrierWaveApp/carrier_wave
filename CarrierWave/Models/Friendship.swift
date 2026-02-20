import Foundation
import SwiftData

// MARK: - FriendshipStatus

enum FriendshipStatus: String, Codable {
    case pending
    case accepted
    case declined
}

// MARK: - Friendship

@Model
nonisolated final class Friendship {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        friendCallsign: String,
        friendUserId: String,
        status: FriendshipStatus = .pending,
        requestedAt: Date = Date(),
        acceptedAt: Date? = nil,
        isOutgoing: Bool
    ) {
        self.id = id
        self.friendCallsign = friendCallsign
        self.friendUserId = friendUserId
        statusRawValue = status.rawValue
        self.requestedAt = requestedAt
        self.acceptedAt = acceptedAt
        self.isOutgoing = isOutgoing
    }

    // MARK: Internal

    var id = UUID()
    var friendCallsign = ""
    var friendUserId = ""
    var statusRawValue = FriendshipStatus.pending.rawValue
    var requestedAt = Date()
    var acceptedAt: Date?
    var isOutgoing = true

    var status: FriendshipStatus {
        get { FriendshipStatus(rawValue: statusRawValue) ?? .pending }
        set { statusRawValue = newValue.rawValue }
    }

    var isAccepted: Bool {
        status == .accepted
    }

    var isPending: Bool {
        status == .pending
    }
}

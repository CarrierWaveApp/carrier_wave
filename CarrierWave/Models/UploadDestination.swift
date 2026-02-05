import CarrierWaveCore
import Foundation
import SwiftData

@Model
final class UploadDestination {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        type: ServiceType,
        isEnabled: Bool = false,
        lastSyncAt: Date? = nil
    ) {
        self.id = id
        self.type = type
        self.isEnabled = isEnabled
        self.lastSyncAt = lastSyncAt
    }

    // MARK: Internal

    var id: UUID
    var type: ServiceType
    var isEnabled: Bool
    var lastSyncAt: Date?
}

// Note: Credentials (API keys, tokens) stored in Keychain, not SwiftData

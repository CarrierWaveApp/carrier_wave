import CarrierWaveCore
import Foundation
import SwiftData

@Model
nonisolated final class UploadDestination {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        type: ServiceType,
        isEnabled: Bool = false,
        lastSyncAt: Date? = nil
    ) {
        self.id = id
        typeRawValue = type.rawValue
        self.isEnabled = isEnabled
        self.lastSyncAt = lastSyncAt
    }

    // MARK: Internal

    var id = UUID()
    @Attribute(originalName: "type")
    var typeRawValue = ServiceType.qrz.rawValue
    var isEnabled: Bool = false
    var lastSyncAt: Date?

    /// Service type enum accessor
    var type: ServiceType {
        get { ServiceType(rawValue: typeRawValue) ?? .qrz }
        set { typeRawValue = newValue.rawValue }
    }
}

// Note: Credentials (API keys, tokens) stored in Keychain, not SwiftData

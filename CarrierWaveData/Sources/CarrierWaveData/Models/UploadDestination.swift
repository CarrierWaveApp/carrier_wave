import CarrierWaveCore
import Foundation
import SwiftData

@Model
nonisolated public final class UploadDestination {
    // MARK: Lifecycle

    public init(
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

    // MARK: Public

    public var id = UUID()
    @Attribute(originalName: "type")
    public var typeRawValue = ServiceType.qrz.rawValue
    public var isEnabled: Bool = false
    public var lastSyncAt: Date?

    public var type: ServiceType {
        get { ServiceType(rawValue: typeRawValue) ?? .qrz }
        set { typeRawValue = newValue.rawValue }
    }
}

import CarrierWaveCore
import Foundation
import SwiftData

@Model
nonisolated public final class ServicePresence {
    // MARK: Lifecycle

    public init(
        id: UUID = UUID(),
        serviceType: ServiceType,
        isPresent: Bool = false,
        needsUpload: Bool = false,
        uploadRejected: Bool = false,
        isSubmitted: Bool = false,
        lastConfirmedAt: Date? = nil,
        qso: QSO? = nil,
        parkReference: String? = nil
    ) {
        self.id = id
        serviceTypeRawValue = serviceType.rawValue
        self.isPresent = isPresent
        self.needsUpload = needsUpload
        self.uploadRejected = uploadRejected
        self.isSubmitted = isSubmitted
        self.lastConfirmedAt = lastConfirmedAt
        self.qso = qso
        self.parkReference = parkReference
    }

    // MARK: Public

    public var id = UUID()
    @Attribute(originalName: "serviceType")
    public var serviceTypeRawValue = ServiceType.qrz.rawValue
    public var isPresent: Bool = false
    public var needsUpload: Bool = false
    public var uploadRejected: Bool = false
    public var isSubmitted: Bool = false
    public var lastConfirmedAt: Date?
    public var parkReference: String?

    /// Whether this record has local changes not yet synced to iCloud
    public var cloudDirtyFlag: Bool = false

    public var qso: QSO?

    /// Service type enum accessor
    public var serviceType: ServiceType {
        get { ServiceType(rawValue: serviceTypeRawValue) ?? .qrz }
        set { serviceTypeRawValue = newValue.rawValue }
    }

    /// Create a presence record for a QSO downloaded from a service
    public static func downloaded(
        from service: ServiceType,
        qso: QSO? = nil,
        parkReference: String? = nil
    ) -> ServicePresence {
        ServicePresence(
            serviceType: service,
            isPresent: true,
            needsUpload: false,
            lastConfirmedAt: Date(),
            qso: qso,
            parkReference: parkReference
        )
    }

    /// Create a presence record for a submitted (but unconfirmed) QSO
    public static func submitted(
        to service: ServiceType,
        qso: QSO? = nil,
        parkReference: String? = nil
    ) -> ServicePresence {
        ServicePresence(
            serviceType: service,
            isPresent: false,
            needsUpload: false,
            isSubmitted: true,
            qso: qso,
            parkReference: parkReference
        )
    }

    /// Create a presence record for a QSO that needs upload
    public static func needsUpload(
        to service: ServiceType,
        qso: QSO? = nil,
        parkReference: String? = nil
    ) -> ServicePresence {
        ServicePresence(
            serviceType: service,
            isPresent: false,
            needsUpload: service.supportsUpload,
            lastConfirmedAt: nil,
            qso: qso,
            parkReference: parkReference
        )
    }
}

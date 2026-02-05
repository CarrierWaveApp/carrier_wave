import CarrierWaveCore
import Foundation
import SwiftData

@Model
final class ServicePresence {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        serviceType: ServiceType,
        isPresent: Bool = false,
        needsUpload: Bool = false,
        uploadRejected: Bool = false,
        lastConfirmedAt: Date? = nil,
        qso: QSO? = nil,
        parkReference: String? = nil
    ) {
        self.id = id
        self.serviceType = serviceType
        self.isPresent = isPresent
        self.needsUpload = needsUpload
        self.uploadRejected = uploadRejected
        self.lastConfirmedAt = lastConfirmedAt
        self.qso = qso
        self.parkReference = parkReference
    }

    // MARK: Internal

    var id: UUID
    var serviceType: ServiceType
    var isPresent: Bool
    var needsUpload: Bool
    /// User explicitly rejected uploading this QSO to this service
    var uploadRejected: Bool = false
    var lastConfirmedAt: Date?
    /// For POTA two-fer activations: the specific park this presence record applies to.
    /// When nil, applies to all parks in the QSO's parkReference (legacy behavior).
    /// When set, allows tracking upload status per-park for multi-park activations.
    var parkReference: String?

    var qso: QSO?

    /// Create a presence record for a QSO that was downloaded from a service
    static func downloaded(
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

    /// Create a presence record for a QSO that needs to be uploaded to a service
    static func needsUpload(
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

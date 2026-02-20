import CarrierWaveCore
import Foundation
import SwiftData

@Model
nonisolated final class ServicePresence {
    // MARK: Lifecycle

    init(
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

    // MARK: Internal

    var id = UUID()
    var serviceTypeRawValue = ServiceType.qrz.rawValue
    var isPresent: Bool = false
    var needsUpload: Bool = false
    /// User explicitly rejected uploading this QSO to this service
    var uploadRejected: Bool = false
    /// Upload HTTP request succeeded but POTA job completion is unconfirmed.
    /// Only used for POTA — other services confirm synchronously.
    var isSubmitted: Bool = false
    var lastConfirmedAt: Date?
    /// For POTA two-fer activations: the specific park this presence record applies to.
    /// When nil, applies to all parks in the QSO's parkReference (legacy behavior).
    /// When set, allows tracking upload status per-park for multi-park activations.
    var parkReference: String?

    /// Whether this record has local changes not yet synced to iCloud.
    var cloudDirtyFlag: Bool = false

    var qso: QSO?

    /// Service type enum accessor
    var serviceType: ServiceType {
        get { ServiceType(rawValue: serviceTypeRawValue) ?? .qrz }
        set { serviceTypeRawValue = newValue.rawValue }
    }

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

    /// Create a presence record for a QSO that was submitted to POTA but not yet job-confirmed
    static func submitted(
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

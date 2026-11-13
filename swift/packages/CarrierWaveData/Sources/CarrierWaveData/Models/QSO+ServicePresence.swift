import Foundation
import SwiftData

// MARK: - QSO Service Presence Helpers

public extension QSO {
    /// Get presence record for a specific service
    func presence(for service: ServiceType) -> ServicePresence? {
        servicePresence.first { !$0.isDeleted && $0.serviceType == service }
    }

    /// Check if QSO is present in a service
    func isPresent(in service: ServiceType) -> Bool {
        presence(for: service)?.isPresent ?? false
    }

    /// Check if QSO needs upload to a service
    func needsUpload(to service: ServiceType) -> Bool {
        servicePresence.contains { !$0.isDeleted && $0.serviceType == service && $0.needsUpload }
    }

    /// Mark QSO as present in a service
    func markPresent(in service: ServiceType, context: ModelContext) {
        if let existing = presence(for: service) {
            existing.isPresent = true
            existing.needsUpload = false
            existing.isSubmitted = false
            existing.lastConfirmedAt = Date()
        } else {
            let newPresence = ServicePresence.downloaded(from: service, qso: self)
            context.insert(newPresence)
            servicePresence.append(newPresence)
        }
    }

    /// Mark QSO as needing upload to a service
    func markNeedsUpload(to service: ServiceType, context: ModelContext) {
        guard service.supportsUpload else {
            return
        }

        if let existing = presence(for: service) {
            if !existing.isPresent {
                existing.needsUpload = true
            }
        } else {
            let newPresence = ServicePresence.needsUpload(to: service, qso: self)
            context.insert(newPresence)
            servicePresence.append(newPresence)
        }
    }

    /// Check if upload to a service was rejected
    func isUploadRejected(for service: ServiceType) -> Bool {
        presence(for: service)?.uploadRejected ?? false
    }

    /// Mark QSO upload as rejected for a service with version gating
    func markUploadRejected(for service: ServiceType, context: ModelContext) {
        let build = ServicePresence.currentAppBuild
        if let existing = presence(for: service) {
            existing.uploadRejected = true
            existing.rejectedAtBuild = build
            existing.needsUpload = false
        } else {
            let newPresence = ServicePresence(
                serviceType: service,
                isPresent: false,
                needsUpload: false,
                uploadRejected: true,
                qso: self
            )
            newPresence.rejectedAtBuild = build
            context.insert(newPresence)
            servicePresence.append(newPresence)
        }
    }

    /// Check if QSO is present in POTA
    func isPresentInPOTA() -> Bool {
        if importSource == .pota {
            return true
        }
        if isPresent(in: .pota) {
            return true
        }
        return false
    }

    /// Get all POTA presence records (may have multiple for two-fers)
    func potaPresenceRecords() -> [ServicePresence] {
        servicePresence.filter { !$0.isDeleted && $0.serviceType == .pota }
    }
}

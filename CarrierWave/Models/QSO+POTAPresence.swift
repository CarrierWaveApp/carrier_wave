// QSO POTA Presence Extension
//
// Per-park POTA presence tracking for two-fer activations.

import CarrierWaveCore
import Foundation
import SwiftData

extension QSO {
    /// Get POTA presence record for a specific park (for two-fer activations)
    func potaPresence(forPark park: String) -> ServicePresence? {
        let normalizedPark = park.uppercased()
        return servicePresence.first {
            $0.serviceType == .pota && $0.parkReference?.uppercased() == normalizedPark
        }
    }

    /// Check if QSO has been uploaded to a specific park
    func isUploadedToPark(_ park: String) -> Bool {
        // First check park-specific presence
        if let parkPresence = potaPresence(forPark: park) {
            return parkPresence.isPresent
        }
        // Fall back to legacy presence (no parkReference) for backward compatibility
        if let legacyPresence = servicePresence.first(where: {
            $0.serviceType == .pota && $0.parkReference == nil
        }) {
            return legacyPresence.isPresent
        }
        return false
    }

    /// Mark QSO as uploaded to a specific park (for two-fer activations)
    func markUploadedToPark(_ park: String, context: ModelContext) {
        let normalizedPark = park.uppercased()

        if let existing = potaPresence(forPark: normalizedPark) {
            existing.isPresent = true
            existing.needsUpload = false
            existing.lastConfirmedAt = Date()
        } else {
            let newPresence = ServicePresence.downloaded(
                from: .pota,
                qso: self,
                parkReference: normalizedPark
            )
            context.insert(newPresence)
            servicePresence.append(newPresence)
        }

        // Also clear the legacy (no parkReference) needsUpload flag if all parks are now uploaded
        clearLegacyNeedsUploadIfFullyUploaded()
    }

    /// Clear the legacy POTA needsUpload flag when all parks have been uploaded.
    /// The legacy record (parkReference == nil) is created by markNeedsUpload(to:) and
    /// must be cleared to prevent repeated upload attempts after per-park uploads complete.
    private func clearLegacyNeedsUploadIfFullyUploaded() {
        guard let legacyPresence = servicePresence.first(where: {
            $0.serviceType == .pota && $0.parkReference == nil && $0.needsUpload
        }) else {
            return
        }

        // Check if all parks are now uploaded
        guard let parkRef = parkReference, !parkRef.isEmpty else {
            // Single/no park reference - clear legacy flag directly
            legacyPresence.needsUpload = false
            legacyPresence.isPresent = true
            legacyPresence.lastConfirmedAt = Date()
            return
        }

        let parks = POTAClient.splitParkReferences(parkRef)
        let allUploaded = parks.allSatisfy { park in
            potaPresence(forPark: park)?.isPresent == true
        }
        if allUploaded {
            legacyPresence.needsUpload = false
            legacyPresence.isPresent = true
            legacyPresence.lastConfirmedAt = Date()
        }
    }

    /// Mark QSO as needing upload to a specific park (for two-fer activations)
    func markNeedsUploadToPark(_ park: String, context: ModelContext) {
        let normalizedPark = park.uppercased()

        if let existing = potaPresence(forPark: normalizedPark) {
            if !existing.isPresent {
                existing.needsUpload = true
            }
        } else {
            let newPresence = ServicePresence.needsUpload(
                to: .pota, qso: self, parkReference: normalizedPark
            )
            context.insert(newPresence)
            servicePresence.append(newPresence)
        }
    }

    /// Get upload status for each park in a two-fer (returns dict of park -> isUploaded)
    func potaUploadStatusByPark() -> [String: Bool] {
        guard let parkRef = parkReference, !parkRef.isEmpty else {
            return [:]
        }
        let parks = POTAClient.splitParkReferences(parkRef)
        return Dictionary(uniqueKeysWithValues: parks.map { ($0, isUploadedToPark($0)) })
    }

    /// Check if QSO needs upload to any park (for two-fer activations)
    func needsUploadToAnyPark() -> Bool {
        guard let parkRef = parkReference, !parkRef.isEmpty else {
            return false
        }
        if isUploadRejected(for: .pota) {
            return false
        }
        let parks = POTAClient.splitParkReferences(parkRef)
        return parks.contains { !isUploadedToPark($0) }
    }

    /// Get list of parks that still need upload (for two-fer activations)
    func parksNeedingUpload() -> [String] {
        guard let parkRef = parkReference, !parkRef.isEmpty else {
            return []
        }
        if isUploadRejected(for: .pota) {
            return []
        }
        let parks = POTAClient.splitParkReferences(parkRef)
        return parks.filter { !isUploadedToPark($0) }
    }
}

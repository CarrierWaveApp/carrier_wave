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
            !$0.isDeleted && $0.serviceType == .pota
                && $0.parkReference?.uppercased() == normalizedPark
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
            existing.isSubmitted = false
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

    /// Mark QSO as submitted (HTTP accepted) to a specific park, pending job confirmation
    func markSubmittedToPark(_ park: String, context: ModelContext) {
        let normalizedPark = park.uppercased()

        if let existing = potaPresence(forPark: normalizedPark) {
            // Don't downgrade from confirmed to submitted
            if !existing.isPresent {
                existing.isSubmitted = true
                existing.needsUpload = false
            } else {
                print("[POTA] markSubmittedToPark: skipped \(callsign) for \(normalizedPark) "
                    + "- already confirmed (isPresent=true)")
            }
        } else {
            let newPresence = ServicePresence.submitted(
                to: .pota,
                qso: self,
                parkReference: normalizedPark
            )
            context.insert(newPresence)
            servicePresence.append(newPresence)
            print("[POTA] markSubmittedToPark: created new submitted presence for "
                + "\(callsign) park=\(normalizedPark)")
        }

        // Clear the legacy needsUpload flag since we've submitted
        clearLegacyNeedsUploadIfSubmitted()
    }

    /// Check if QSO has been submitted (but not yet confirmed) to a specific park
    func isSubmittedToPark(_ park: String) -> Bool {
        if let parkPresence = potaPresence(forPark: park) {
            return parkPresence.isSubmitted && !parkPresence.isPresent
        }
        // Fall back to legacy presence for backward compatibility
        if let legacyPresence = servicePresence.first(where: {
            $0.serviceType == .pota && $0.parkReference == nil
        }) {
            return legacyPresence.isSubmitted && !legacyPresence.isPresent
        }
        return false
    }

    /// Confirm a submitted upload after POTA job completed successfully
    func confirmUploadedToPark(_ park: String, context: ModelContext) {
        print("[POTA] confirmUploadedToPark: \(callsign) park=\(park.uppercased())")
        markUploadedToPark(park, context: context)
    }

    /// Reset a submitted upload back to needing upload (e.g., POTA job failed)
    func resetSubmittedToPark(_ park: String, context: ModelContext) {
        let normalizedPark = park.uppercased()

        if let existing = potaPresence(forPark: normalizedPark) {
            print("[POTA] resetSubmittedToPark: \(callsign) park=\(normalizedPark) "
                + "- was isPresent=\(existing.isPresent), isSubmitted=\(existing.isSubmitted)")
            existing.isSubmitted = false
            existing.needsUpload = true
            existing.isPresent = false
        } else {
            print("[POTA] resetSubmittedToPark: \(callsign) park=\(normalizedPark) "
                + "- no presence record found")
        }
    }

    /// Force reset all POTA presence for a specific park back to needing upload.
    /// Used by the debug "Force Reupload" feature.
    func forceResetParkUpload(_ park: String, context: ModelContext) {
        let normalizedPark = park.uppercased()

        if let existing = potaPresence(forPark: normalizedPark) {
            print("[POTA] forceResetParkUpload: \(callsign) park=\(normalizedPark) "
                + "- was isPresent=\(existing.isPresent), isSubmitted=\(existing.isSubmitted), "
                + "needsUpload=\(existing.needsUpload)")
            existing.isPresent = false
            existing.isSubmitted = false
            existing.needsUpload = true
            existing.uploadRejected = false
            existing.lastConfirmedAt = nil
        }

        // Also reset legacy presence if it exists
        if let legacyPresence = servicePresence.first(where: {
            $0.serviceType == .pota && $0.parkReference == nil
        }) {
            legacyPresence.isPresent = false
            legacyPresence.isSubmitted = false
            legacyPresence.needsUpload = true
            legacyPresence.uploadRejected = false
        }
    }

    /// Clear the legacy POTA needsUpload flag when all parks have been uploaded.
    /// The legacy record (parkReference == nil) is created by markNeedsUpload(to:) and
    /// must be cleared to prevent repeated upload attempts after per-park uploads complete.
    private func clearLegacyNeedsUploadIfFullyUploaded() {
        guard
            let legacyPresence = servicePresence.first(where: {
                $0.serviceType == .pota && $0.parkReference == nil && $0.needsUpload
            })
        else {
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

    /// Clear the legacy POTA needsUpload flag when all parks have been submitted.
    private func clearLegacyNeedsUploadIfSubmitted() {
        guard
            let legacyPresence = servicePresence.first(where: {
                $0.serviceType == .pota && $0.parkReference == nil && $0.needsUpload
            })
        else {
            return
        }

        guard let parkRef = parkReference, !parkRef.isEmpty else {
            legacyPresence.needsUpload = false
            legacyPresence.isSubmitted = true
            return
        }

        let parks = POTAClient.splitParkReferences(parkRef)
        let allSubmittedOrUploaded = parks.allSatisfy { park in
            let presence = potaPresence(forPark: park)
            return presence?.isPresent == true || presence?.isSubmitted == true
        }
        if allSubmittedOrUploaded {
            legacyPresence.needsUpload = false
            legacyPresence.isSubmitted = true
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

    /// Check if QSO has been submitted (but not confirmed) to any park
    func isSubmittedToAnyPark() -> Bool {
        guard let parkRef = parkReference, !parkRef.isEmpty else {
            return servicePresence.contains {
                $0.serviceType == .pota && $0.isSubmitted && !$0.isPresent
            }
        }
        let parks = POTAClient.splitParkReferences(parkRef)
        return parks.contains { isSubmittedToPark($0) }
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

// POTA Activation Upload Snapshot
//
// Precomputes per-activation upload status (pending/submitted/uploaded counts,
// rejected/fully-uploaded flags, parks needing upload, summary text) by walking
// each QSO's servicePresence relationship exactly once. The resulting struct is
// pure value data — reading it never traverses SwiftData, so it is safe to read
// from a SwiftUI view body even while CKSyncEngine is mutating the persistent
// store on a background thread.

import CarrierWaveData
import Foundation

extension POTAActivation {
    struct UploadSnapshot {
        let pendingCount: Int
        let submittedCount: Int
        let uploadedCount: Int
        let isFullyUploaded: Bool
        let isRejected: Bool
        let parksNeedingUpload: [String]
        let uploadStatusSummary: String?
    }

    /// Captures every (qso, park) presence flag we will need into local arrays so
    /// no further SwiftData relationship reads happen after this returns.
    static func captureFlags(qsos: [QSO], parks: [String]) -> [QSOFlags] {
        qsos.map { qso in
            let perPark = parks.map { park in
                ParkFlags(
                    uploaded: qso.isUploadedToPark(park),
                    submitted: qso.isSubmittedToPark(park)
                )
            }
            return QSOFlags(
                rejected: qso.isUploadRejected(for: .pota),
                presentInPOTA: qso.isPresentInPOTA(),
                perPark: perPark
            )
        }
    }

    static func computeUploadSnapshot(
        qsos: [QSO],
        parks: [String]
    ) -> UploadSnapshot {
        let flags = captureFlags(qsos: qsos, parks: parks)
        let qsoCounts = qsoLevelCounts(flags: flags)
        let parkCounts = parkLevelCounts(flags: flags, parks: parks)
        return UploadSnapshot(
            pendingCount: qsoCounts.pending,
            submittedCount: qsoCounts.submitted,
            uploadedCount: qsoCounts.uploaded,
            isFullyUploaded: parkCounts.fullyUploaded,
            isRejected: qsoCounts.isRejected,
            parksNeedingUpload: parkCounts.parksNeedingUpload,
            uploadStatusSummary: summary(parkCounts: parkCounts, parkTotal: parks.count)
        )
    }

    struct ParkFlags {
        let uploaded: Bool
        let submitted: Bool
    }

    struct QSOFlags {
        let rejected: Bool
        let presentInPOTA: Bool
        let perPark: [ParkFlags]
    }

    private struct QSOLevelCounts {
        let pending: Int
        let submitted: Int
        let uploaded: Int
        let isRejected: Bool
    }

    private struct ParkLevelCounts {
        let fullyUploaded: Bool
        let acceptedParks: Int
        let submittedParks: Int
        let parksNeedingUpload: [String]
    }

    private static func qsoLevelCounts(flags: [QSOFlags]) -> QSOLevelCounts {
        var pending = 0
        var submitted = 0
        var uploaded = 0
        var notUploadedCount = 0
        var notUploadedRejectedCount = 0
        for qso in flags {
            if !qso.presentInPOTA {
                notUploadedCount += 1
                if qso.rejected {
                    notUploadedRejectedCount += 1
                }
            }
            let allParksUp = !qso.perPark.isEmpty && qso.perPark.allSatisfy(\.uploaded)
            if allParksUp {
                uploaded += 1
                continue
            }
            if !qso.rejected, qso.perPark.contains(where: \.submitted) {
                submitted += 1
            }
            if !qso.rejected,
               qso.perPark.contains(where: { !$0.uploaded && !$0.submitted })
            {
                pending += 1
            }
        }
        let isRejected = notUploadedCount > 0 && notUploadedRejectedCount == notUploadedCount
        return QSOLevelCounts(
            pending: pending,
            submitted: submitted,
            uploaded: uploaded,
            isRejected: isRejected
        )
    }

    private static func parkLevelCounts(
        flags: [QSOFlags],
        parks: [String]
    ) -> ParkLevelCounts {
        var fullyUploaded = !parks.isEmpty
        var accepted = 0
        var submittedParks = 0
        var needingUpload: [String] = []
        for (idx, park) in parks.enumerated() {
            let parkAccepted = flags.allSatisfy { $0.perPark[idx].uploaded || $0.rejected }
            if parkAccepted {
                accepted += 1
            } else {
                fullyUploaded = false
            }
            if flags.contains(where: { $0.perPark[idx].submitted }) {
                submittedParks += 1
            }
            let parkNeedsUpload = flags.contains { qso in
                !qso.perPark[idx].uploaded && !qso.perPark[idx].submitted && !qso.rejected
            }
            if parkNeedsUpload {
                needingUpload.append(park)
            }
        }
        return ParkLevelCounts(
            fullyUploaded: fullyUploaded,
            acceptedParks: accepted,
            submittedParks: submittedParks,
            parksNeedingUpload: needingUpload
        )
    }

    private static func summary(parkCounts: ParkLevelCounts, parkTotal: Int) -> String? {
        guard parkTotal > 1 else {
            return nil
        }
        let accepted = parkCounts.acceptedParks
        let submitted = parkCounts.submittedParks
        if accepted == parkTotal {
            return "\(accepted)/\(parkTotal) parks accepted"
        }
        if submitted > 0, accepted > 0 {
            return "\(accepted) accepted, \(submitted) submitted"
        }
        if submitted > 0 {
            return "\(submitted)/\(parkTotal) parks submitted"
        }
        return "\(accepted)/\(parkTotal) parks accepted"
    }
}

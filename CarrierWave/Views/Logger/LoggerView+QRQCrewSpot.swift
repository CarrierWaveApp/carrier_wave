import CarrierWaveData
import SwiftUI

// MARK: - LoggerView QRQ Crew Spot

extension LoggerView {
    // MARK: - QRQ Crew Spot

    /// Check if both operators are QRQ Crew members and trigger spot flow.
    /// QRQ Crew spots only apply on UTC Fridays.
    func checkQRQCrewSpot(
        theirCallsign: String,
        theirQRZInfo: CallsignInfo? = nil
    ) {
        // QRQ Crew spots only apply on UTC Fridays
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        guard utcCalendar.component(.weekday, from: Date()) == 6 else {
            return
        }

        guard let session = sessionManager?.activeSession,
              session.isPOTA,
              let parkRef = session.parkReference
        else {
            return
        }

        let myCallsign = session.myCallsign
        guard !myCallsign.isEmpty, !theirCallsign.isEmpty else {
            return
        }

        Task {
            // Look up user's own callsign for QRZ nickname
            let myQRZInfo = await CallsignLookupService(
                modelContext: modelContext
            ).lookup(myCallsign)

            guard var spotInfo = await QRQCrewService.checkMembership(
                myCallsign: myCallsign,
                theirCallsign: theirCallsign,
                myQRZInfo: myQRZInfo,
                theirQRZInfo: theirQRZInfo
            ) else {
                return
            }

            // Get fastest RBN WPM from spot comments
            let fastestWPM: Int? = await MainActor.run {
                let comments = sessionManager?.spotCommentsService.comments ?? []
                let wpms = comments.filter(\.isAutomatedSpot).compactMap(\.wpm)
                return wpms.max()
            }

            // Fill in the park reference and RBN WPM
            spotInfo = QRQCrewSpotInfo(
                myInfo: spotInfo.myInfo,
                theirInfo: spotInfo.theirInfo,
                parkReference: parkRef,
                rbnWPM: fastestWPM
            )

            await MainActor.run {
                pendingQRQCrewSpot = spotInfo
                showQRQCrewSpotSheet = true
            }
        }
    }

    /// Post the QRQ Crew spot message to POTA
    func postQRQCrewSpot(spotInfo: QRQCrewSpotInfo, wpm: Int) async {
        guard wpm >= QRQCrewService.minimumWPM else {
            return
        }

        let comment = spotInfo.spotComment(wpm: wpm)
        await sessionManager?.postSpot(comment: comment, showToast: true)

        await MainActor.run {
            pendingQRQCrewSpot = nil
        }
    }
}

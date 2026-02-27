import SwiftUI

// MARK: - LoggerView QRQ Crew Spot

extension LoggerView {
    // MARK: - QRQ Crew Spot

    /// Check if both operators are QRQ Crew members and trigger spot flow
    func checkQRQCrewSpot(
        theirCallsign: String,
        theirQRZInfo: CallsignInfo? = nil
    ) {
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

            // Fill in the park reference
            spotInfo = QRQCrewSpotInfo(
                myInfo: spotInfo.myInfo,
                theirInfo: spotInfo.theirInfo,
                parkReference: parkRef
            )

            await MainActor.run {
                let autoSpot = UserDefaults.standard.bool(forKey: "qrqCrewAutoSpot")
                let lastWPM = UserDefaults.standard.integer(forKey: "qrqCrewLastWPM")

                if autoSpot, lastWPM >= QRQCrewService.minimumWPM {
                    // Auto-post with last-used WPM, no prompt
                    Task { await postQRQCrewSpot(spotInfo: spotInfo, wpm: lastWPM) }
                } else {
                    // Show prompt for WPM and confirmation
                    pendingQRQCrewSpot = spotInfo
                    showQRQCrewSpotSheet = true
                }
            }
        }
    }

    /// Post the QRQ Crew spot message to POTA
    func postQRQCrewSpot(spotInfo: QRQCrewSpotInfo, wpm: Int) async {
        guard wpm >= QRQCrewService.minimumWPM else {
            return
        }

        // Save the WPM for next auto-spot
        UserDefaults.standard.set(wpm, forKey: "qrqCrewLastWPM")

        let comment = spotInfo.spotComment(wpm: wpm)
        await sessionManager?.postSpot(comment: comment, showToast: true)

        await MainActor.run {
            pendingQRQCrewSpot = nil
        }
    }
}

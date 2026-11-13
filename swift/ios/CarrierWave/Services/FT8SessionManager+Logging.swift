//
//  FT8SessionManager+Logging.swift
//  CarrierWave
//

import CarrierWaveCore
import CarrierWaveData
import Foundation
import OSLog
import UIKit

// MARK: - QSO Logging

extension FT8SessionManager {
    func logCompletedQSO(_ completed: FT8QSOStateMachine.CompletedQSO) {
        let rstSent = formatReport(completed.myReport)
        let rstReceived = formatReport(completed.theirReport)

        qsoLogger.logFT8QSO(FT8CompletedQSOData(
            callsign: completed.theirCallsign,
            band: selectedBand,
            frequency: selectedFrequency,
            rstSent: rstSent,
            rstReceived: rstReceived,
            theirGrid: completed.theirGrid
        ))

        qsoCount += 1
        decodeEnricher.markWorkedThisSession(completed.theirCallsign)
        FT8SessionManager.log.info("FT8 QSO logged: \(completed.theirCallsign)")

        UINotificationFeedbackGenerator().notificationOccurred(.success)

        // POTA milestone: extra haptic when reaching 10 valid QSOs
        if qsoCount == 10 {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    func formatReport(_ report: Int?) -> String {
        guard let report else {
            return "+00" // Neutral fallback for unknown FT8 dB report
        }
        let sign = report >= 0 ? "+" : "-"
        return "\(sign)\(String(format: "%02d", abs(report)))"
    }
}

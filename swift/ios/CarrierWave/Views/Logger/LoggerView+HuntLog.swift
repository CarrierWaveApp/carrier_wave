import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - LoggerView HUNT one-off log

extension LoggerView {
    /// Log a one-off HUNT QSO at a different frequency/mode without changing the
    /// active session. The argument string after `HUNT` is parsed by the shared
    /// `QuickEntryParser`, so all standard quick-entry tokens (RST, park, grid,
    /// state, notes, Zulu time) flow through.
    func executeHuntLog(_ result: QuickEntryResult) {
        guard let session = sessionManager?.activeSession else {
            ToastManager.shared.warning("Start a session first")
            return
        }

        // HUNT only really has a point as an *off-frequency* / *different-mode* log
        // — fall back to the session's freq/mode for whichever the user omitted.
        // A pure callsign-only HUNT is rejected by parseHunt and never reaches here.
        // session.mode is non-optional; session.frequency can be nil if the session
        // was started without a frequency yet.
        let mode = result.mode ?? session.mode
        guard let frequency = result.frequency ?? session.frequency else {
            ToastManager.shared.error("Set a frequency on the session first, or pass one to HUNT")
            return
        }

        let callsign = result.callsign.uppercased()
        let rstDefault = mode == "CW" || mode == "FT8" || mode == "FT4" ? "599" : "59"
        let logged = sessionManager?.logQSO(
            callsign: callsign,
            rstSent: result.rstSent ?? rstDefault,
            rstReceived: result.rstReceived ?? rstDefault,
            theirGrid: result.theirGrid,
            theirParkReference: result.theirPark,
            notes: result.notes,
            state: result.state,
            frequencyOverride: result.frequency,
            modeOverride: result.mode,
            timestampOverride: result.zuluTime?.dateToday()
        )

        guard let logged else {
            ToastManager.shared.error("Failed to log QSO")
            return
        }

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        refreshSessionQSOs()
        ToastManager.shared.success(
            "Logged \(callsign) at \(FrequencyFormatter.formatWithUnit(frequency)) \(mode)"
        )

        // Fire-and-forget callsign lookup to enrich the QSO with name/grid/state/etc.
        Task { await fetchAndUpdateQSOMetadata(id: logged.id, callsign: callsign) }
    }
}

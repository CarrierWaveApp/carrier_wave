import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - LoggerView command routing (shared Rust handler)

extension LoggerView {
    /// Route a detected command through the shared Rust `LoggerCommandApi` — the
    /// same handler Android runs. State commands (FREQ/MODE/MYCALL/NOTE/session-
    /// metadata) execute in Rust and come back as `sessionUpdated`; spot + panel
    /// commands come back as intents this maps to the native effects/UI. Falls
    /// back to the fully-native `executeCommand` when the store seam is off.
    func runLoggerCommand(_ text: String, fallback command: LoggerCommand) {
        guard let api = LoggerCommandApiRegistry.current,
              let session = sessionManager?.activeSession
        else {
            executeCommand(command)
            return
        }
        let context = FfiCommandContext(
            potaQsySpotEnabled: UserDefaults.standard.object(forKey: "potaQSYSpotEnabled") as? Bool ?? true,
            potaAutoSpotEnabled: UserDefaults.standard.object(forKey: "potaAutoSpotEnabled") as? Bool ?? false
        )
        let sessionId = SwiftDataStoreImporter.uuid(session.id)
        guard let outcome = try? api.handleText(sessionId: sessionId, input: text, context: context)
        else {
            executeCommand(command)
            return
        }
        applyCommandOutcome(outcome, fallback: command)
    }

    private func applyCommandOutcome(_ outcome: FfiCommandOutcome, fallback command: LoggerCommand) {
        switch outcome {
        case let .sessionUpdated(session, notice, tunedFrequencyMhz, promptQsySpot, autoSpotFirstSet):
            guard sessionManager?.applyCommandSessionUpdate(
                session, tunedFrequency: tunedFrequencyMhz, autoSpotFirstSet: autoSpotFirstSet
            ) == true else {
                executeCommand(command)
                return
            }
            ToastManager.shared.success(notice)
            if promptQsySpot {
                qsyNewFrequency = tunedFrequencyMhz
                showQSYSpotConfirmation = true
            }
        case let .postSpot(comment):
            Task { await postSpot(comment: comment) }
        case let .startRepeatSpot(comment, intervalMinutes):
            executeSpotCommand(comment: comment, repeatMinutes: Int(intervalMinutes))
        case .stopRepeatSpot:
            executeSpotStopCommand()
        case .logQso,
             .present:
            // The one-off HUNT log + panel presentation stay native (UI / services
            // that can't live in Rust); the handler already validated + decided.
            executeCommand(command)
        case let .message(level, text):
            showCommandMessage(level, text)
        }
    }

    private func showCommandMessage(_ level: FfiMessageLevel, _ text: String) {
        switch level {
        case .error: ToastManager.shared.error(text)
        case .warning: ToastManager.shared.warning(text)
        case .success: ToastManager.shared.success(text)
        case .info: ToastManager.shared.info(text)
        }
    }
}

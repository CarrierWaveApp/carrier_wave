import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - LoggerView Commands

extension LoggerView {
    // MARK: - Command Execution

    func executeCommand(_ command: LoggerCommand) {
        switch command {
        case .frequency,
             .mode,
             .myCall,
             .sessionMetadata: executeSessionFieldCommand(command)
        case let .spot(comment, repeatMinutes): executeSpotCommand(comment: comment, repeatMinutes: repeatMinutes)
        case .spotStop: executeSpotStopCommand()
        case let .rbn(callsign): executeRBNCommand(callsign)
        case .p2p: executeP2PCommand()
        case .s2s: executeS2SCommand()
        case .map: executeMapCommand()
        case let .note(text): executeNoteCommand(text)
        case .manual: executeManualCommand()
        case .checklist: FieldGuideLinker.openChecklists(radioName: sessionManager?.activeSession?.myRig)
        case .replay: executeReplayCommand()
        case let .huntLog(result): executeHuntLog(result)
        default: executeSheetCommand(command)
        }
    }

    /// Commands that write session fields (frequency, mode, callsign, or the
    /// combined session-metadata line).
    func executeSessionFieldCommand(_ command: LoggerCommand) {
        switch command {
        case let .frequency(freq): executeFrequencyCommand(freq)
        case let .mode(newMode): executeModeCommand(newMode)
        case let .myCall(call): executeMyCallCommand(call)
        case let .sessionMetadata(entry): executeSessionMetadataCommand(entry)
        default: break
        }
    }

    func executeSheetCommand(_ command: LoggerCommand) {
        switch command {
        case .hunt:
            if sessionManager?.activeSession?.isRove == true {
                showNextStopSheet = true
            } else if let onSpotCommand {
                onSpotCommand(.showHunt)
            } else {
                present(.pota)
            }
        case .solar: present(.solar)
        case .weather: present(.weather)
        case .hidden: showHiddenQSOsSheet = true
        case .help: showHelpSheet = true
        case .websdr: present(.webSDR)
        case .band: showBandEditSheet = true
        case .rig: showRigEditSheet = true
        case .radio: present(.radio)
        default: break
        }
    }

    func executeManualCommand() {
        guard let radio = sessionManager?.activeSession?.myRig,
              !radio.isEmpty
        else {
            ToastManager.shared.warning("No radio selected")
            return
        }
        guard FieldGuideLinker.hasManual(for: radio) else {
            ToastManager.shared.warning("No manual found for \(radio)")
            return
        }
        FieldGuideLinker.openManual(for: radio)
    }

    func executeFrequencyCommand(_ freq: Double) {
        let result = sessionManager?.updateFrequency(freq)

        if result?.isFirstFrequencySet == true {
            let band = LoggingSession.bandForFrequency(freq)
            ToastManager.shared.success(
                "Frequency set to \(FrequencyFormatter.formatWithUnit(freq)) (\(band))"
            )
        } else {
            ToastManager.shared.commandExecuted(
                "FREQ", result: FrequencyFormatter.formatWithUnit(freq)
            )
        }

        // Auto-switch mode based on frequency segment (if enabled)
        if autoModeSwitch, let suggestedMode = result?.suggestedMode {
            _ = sessionManager?.updateMode(suggestedMode)
            ToastManager.shared.commandExecuted("MODE", result: "\(suggestedMode) (auto)")
        }

        // Prompt for QSY spot
        if result?.shouldPromptForSpot == true {
            qsyNewFrequency = freq
            showQSYSpotConfirmation = true
        }
    }

    /// Apply a multi-field session update ("14.046 CW CN87") to the active
    /// session. Everything set here changes QSOs logged from now on — the
    /// toast says so explicitly, and tokens the session can't take are called
    /// out instead of silently dropped.
    func executeSessionMetadataCommand(_ entry: SessionMetadataEntry) {
        guard sessionManager?.activeSession != nil else {
            ToastManager.shared.warning("Start a session first")
            return
        }

        var applied: [String] = []
        var freqResult: FrequencyUpdateResult?

        if let freq = entry.frequency {
            freqResult = sessionManager?.updateFrequency(freq)
            let band = entry.band.map { " (\($0))" } ?? ""
            applied.append("\(FrequencyFormatter.formatWithUnit(freq))\(band)")
        }

        if let mode = entry.mode {
            _ = sessionManager?.updateMode(mode)
            applied.append(mode)
        } else if entry.frequency != nil, autoModeSwitch,
                  let suggestedMode = freqResult?.suggestedMode
        {
            // Only auto-switch when the user didn't set a mode explicitly.
            _ = sessionManager?.updateMode(suggestedMode)
            applied.append("\(suggestedMode) (auto)")
        }

        if let grid = entry.grid {
            sessionManager?.updateMyGrid(grid)
            applied.append("grid \(grid)")
        }

        ToastManager.shared.success(
            "Session set for future QSOs: \(applied.joined(separator: " · "))"
        )
        if !entry.unsupported.isEmpty {
            ToastManager.shared.warning(
                "Can't set on session: \(entry.unsupported.joined(separator: ", "))"
            )
        }

        if freqResult?.shouldPromptForSpot == true {
            qsyNewFrequency = entry.frequency
            showQSYSpotConfirmation = true
        }
    }

    func executeModeCommand(_ newMode: String) {
        let shouldPromptForSpot = sessionManager?.updateMode(newMode) ?? false
        ToastManager.shared.commandExecuted("MODE", result: newMode)
        if shouldPromptForSpot {
            qsyNewFrequency = sessionManager?.activeSession?.frequency
            showQSYSpotConfirmation = true
        }
    }

    func executeRBNCommand(_ callsign: String?) {
        if let onSpotCommand {
            onSpotCommand(.showRBN(callsign: callsign))
        } else {
            rbnTargetCallsign = callsign
            present(.rbn)
        }
    }

    func executeS2SCommand() {
        // S2S only makes sense during a SOTA activation.
        guard sessionManager?.activeSession?.isSOTA == true else {
            ToastManager.shared.error("S2S is only available during SOTA activations")
            return
        }
        // Force-refresh (bypass freshness window so the user gets fresh
        // data) and tell them how many activators are on the air. The
        // auto-enrichment in `updateSOTASpotMatches` will fill the Summit
        // field as soon as they type a matching callsign — this command
        // is the surfacing hint that those spots exist. A dedicated picker
        // sheet is planned.
        Task {
            await SOTASpotsCache.shared.refreshNow()
            await MainActor.run {
                cachedSOTASpots = SOTASpotsCache.shared.spotsSync()
                let count = cachedSOTASpots.count
                if count == 0 {
                    ToastManager.shared.info("No SOTA activators currently spotted")
                } else {
                    ToastManager.shared.info(
                        "\(count) SOTA station\(count == 1 ? "" : "s") on the air — "
                            + "type a callsign to auto-fill summit"
                    )
                }
            }
        }
    }

    func executeP2PCommand() {
        // P2P only works during POTA activations
        guard sessionManager?.activeSession?.isPOTA == true else {
            ToastManager.shared.error("P2P is only available during POTA activations")
            return
        }

        // Check for user grid
        let myGrid =
            sessionManager?.activeSession?.myGrid
                ?? UserDefaults.standard.string(forKey: "loggerDefaultGrid")

        if myGrid == nil || myGrid?.isEmpty == true {
            ToastManager.shared.error("Set your grid in session settings to find P2P opportunities")
            return
        }

        if let onSpotCommand {
            onSpotCommand(.showP2P)
        } else {
            present(.p2p)
        }
    }

    func executeMapCommand() {
        // Check for missing grid configuration
        let myGrid =
            sessionManager?.activeSession?.myGrid
                ?? UserDefaults.standard.string(forKey: "loggerDefaultGrid")

        if myGrid == nil || myGrid?.isEmpty == true {
            ToastManager.shared.warning("Your grid is not set - no arcs will be shown")
        } else {
            checkSessionGridWarnings()
        }

        // On iPad, switch to the sidebar map tab instead of opening an overlay
        if let onSpotCommand {
            onSpotCommand(.showMap)
        } else {
            present(.map)
        }
    }

    func checkSessionGridWarnings() {
        let qsosWithGrid = sessionQSOs.filter {
            $0.theirGrid != nil && !$0.theirGrid!.isEmpty
        }

        if !sessionQSOs.isEmpty, qsosWithGrid.isEmpty {
            ToastManager.shared.warning(
                "No QSOs have grids - add QRZ Callsign Lookup in Settings \u{2192} Data & Tools"
            )
        } else if sessionQSOs.count > qsosWithGrid.count {
            let missing = sessionQSOs.count - qsosWithGrid.count
            ToastManager.shared.info(
                "\(missing) QSO\(missing == 1 ? "" : "s") missing grid"
            )
        }
    }

    func executeMyCallCommand(_ callsign: String) {
        guard sessionManager?.activeSession != nil else {
            ToastManager.shared.warning("Start a session first")
            return
        }
        sessionManager?.activeSession?.myCallsign = callsign
        ToastManager.shared.commandExecuted("MYCALL", result: callsign)
    }

    func executeNoteCommand(_ text: String) {
        sessionManager?.appendNote(text)
        ToastManager.shared.commandExecuted("NOTE", result: "Added to session log")
    }

    func executeReplayCommand() {
        guard let session = sessionManager?.webSDRSession,
              session.state == .recording || session.state == .paused
        else {
            ToastManager.shared.warning("No active SDR recording")
            return
        }
        guard session.replayEngine.availableHistorySeconds > 1 else {
            ToastManager.shared.warning("Not enough audio captured yet")
            return
        }
        session.replayLastAudio()
        ToastManager.shared.info("Replaying last SDR audio")
    }

    func executeSpotCommand(comment: String?, repeatMinutes: Int?) {
        if let repeatMinutes {
            sessionManager?.startRepeatSpot(comment: comment, intervalMinutes: repeatMinutes)
            if let comment, !comment.isEmpty {
                ToastManager.shared.success("Spotting \"\(comment)\" every \(repeatMinutes)m")
            } else {
                ToastManager.shared.success("Auto-spotting every \(repeatMinutes)m")
            }
        } else {
            Task { await postSpot(comment: comment) }
        }
    }

    func executeSpotStopCommand() {
        sessionManager?.stopRepeatSpot()
        ToastManager.shared.commandExecuted("SPOT", result: "Repeat stopped")
    }

    // MARK: - Spot Posting

    func postSpot(comment: String? = nil) async {
        guard let session = sessionManager?.activeSession else {
            ToastManager.shared.error("Start a session first")
            return
        }
        guard session.isPOTA || session.isSOTA else {
            ToastManager.shared.error("SPOT requires a POTA or SOTA session")
            return
        }
        guard session.frequency != nil else {
            ToastManager.shared.error("SPOT requires a frequency")
            return
        }
        if session.isPOTA, session.parkReference == nil {
            ToastManager.shared.error("POTA spot needs a park reference")
            return
        }
        if session.isSOTA,
           (session.sotaReference ?? "").isEmpty
        {
            ToastManager.shared.error("SOTA spot needs a summit reference")
            return
        }
        guard !(session.myCallsign).isEmpty else {
            ToastManager.shared.error("No callsign configured")
            return
        }

        await sessionManager?.postSpot(comment: comment, showToast: true)
    }

    // MARK: - QSY URI Handlers

    /// Handle qsy://spot notification — pre-fill logger form from URI parameters
    func handleQSYSpotNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let callsign = userInfo["callsign"] as? String,
              sessionManager?.activeSession != nil
        else {
            if sessionManager?.activeSession == nil {
                ToastManager.shared.warning("Start a session first")
            }
            return
        }

        preSpotFrequency = sessionManager?.selfSpotFrequency
        callsignInput = callsign

        if let freqMHz = userInfo["frequencyMHz"] as? Double {
            _ = sessionManager?.updateFrequency(freqMHz, isTuningToSpot: true)
        }

        if let mode = userInfo["mode"] as? String {
            _ = sessionManager?.updateMode(mode)
        }

        var noteParts: [String] = []
        if let ref = userInfo["ref"] as? String {
            noteParts.append(ref)
        }
        if let comment = userInfo["comment"] as? String {
            noteParts.append(comment)
        }
        if !noteParts.isEmpty {
            notes = noteParts.joined(separator: " - ")
        }

        let freqStr = (userInfo["frequencyMHz"] as? Double)
            .map { " on \(FrequencyFormatter.formatWithUnit($0))" } ?? ""
        ToastManager.shared.info("QSY: \(callsign)\(freqStr)")
    }

    /// Handle qsy://tune notification — tune radio and update session frequency
    func handleQSYTuneNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let freqMHz = userInfo["frequencyMHz"] as? Double
        else {
            return
        }

        if sessionManager?.activeSession != nil {
            _ = sessionManager?.updateFrequency(freqMHz, isTuningToSpot: true)
        } else {
            RadioService.shared.setFrequency(freqMHz)
        }

        if let mode = userInfo["mode"] as? String {
            _ = sessionManager?.updateMode(mode)
        }

        let modeStr = (userInfo["mode"] as? String).map { " \($0)" } ?? ""
        ToastManager.shared.info(
            "Tuned to \(FrequencyFormatter.formatWithUnit(freqMHz))\(modeStr)"
        )
    }

    /// Handle qsy://log notification — show confirmation sheet with pre-filled QSO data
    func handleQSYLogNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let callsign = userInfo["callsign"] as? String,
              let freqMHz = userInfo["frequencyMHz"] as? Double,
              let mode = userInfo["mode"] as? String,
              sessionManager?.activeSession != nil
        else {
            if sessionManager?.activeSession == nil {
                ToastManager.shared.warning("Start a session first")
            }
            return
        }

        pendingQSYLog = QSYLogConfirmation(
            callsign: callsign,
            frequencyMHz: freqMHz,
            mode: mode,
            rstSent: userInfo["rstSent"] as? String,
            rstReceived: userInfo["rstReceived"] as? String,
            grid: userInfo["grid"] as? String,
            ref: userInfo["ref"] as? String,
            refType: userInfo["refType"] as? String,
            time: userInfo["time"] as? Date,
            contest: userInfo["contest"] as? String,
            srx: userInfo["srx"] as? String,
            stx: userInfo["stx"] as? String,
            source: userInfo["source"] as? String,
            comment: userInfo["comment"] as? String
        )
    }

    /// Confirm and log QSO from qsy://log data
    func confirmQSYLog(_ confirmation: QSYLogConfirmation) {
        _ = sessionManager?.updateFrequency(
            confirmation.frequencyMHz, isTuningToSpot: true
        )
        _ = sessionManager?.updateMode(confirmation.mode)

        callsignInput = confirmation.callsign
        rstSent = confirmation.rstSent ?? defaultRST
        rstReceived = confirmation.rstReceived ?? defaultRST
        if let grid = confirmation.grid {
            theirGrid = grid
        }
        if let ref = confirmation.ref {
            theirPark = ref
        }
        if let comment = confirmation.comment {
            notes = comment
        }

        logQSO()

        pendingQSYLog = nil
        ToastManager.shared.success("Logged \(confirmation.callsign)")
    }

    /// Cancel the current spot and restore session frequency
    func cancelSpot() {
        if let freq = preSpotFrequency {
            _ = sessionManager?.updateFrequency(freq, isTuningToSpot: true)
            preSpotFrequency = nil
        }
        callsignInput = ""
        notes = ""
        lookupResult = nil
        lookupError = nil
        quickEntryResult = nil
        quickEntryMultiResults = nil
        quickEntryTokens = []
        lastLookedUpCallsigns = []
        ToastManager.shared.info("Spot cancelled")
    }
}

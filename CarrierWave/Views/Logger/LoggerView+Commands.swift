import CarrierWaveData
import SwiftUI

// MARK: - LoggerView Commands

extension LoggerView {
    // MARK: - Command Execution

    func executeCommand(_ command: LoggerCommand) {
        switch command {
        case let .frequency(freq): executeFrequencyCommand(freq)
        case let .mode(newMode): executeModeCommand(newMode)
        case let .spot(comment): Task { await postSpot(comment: comment) }
        case let .rbn(callsign): executeRBNCommand(callsign)
        case .p2p: executeP2PCommand()
        case .map: executeMapCommand()
        case let .note(text): executeNoteCommand(text)
        case .manual: executeManualCommand()
        case .checklist: FieldGuideLinker.openChecklists(radioName: sessionManager?.activeSession?.myRig)
        default: executeSheetCommand(command)
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
                showPOTAPanel = true
            }
        case .solar: showSolarPanel = true
        case .weather: showWeatherPanel = true
        case .hidden: showHiddenQSOsSheet = true
        case .help: showHelpSheet = true
        case .websdr: showWebSDRPanel = true
        case .band: showBandEditSheet = true
        case .rig: showRigEditSheet = true
        case .radio: showBLERadioPanel = true
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
            showRBNPanel = true
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
            showP2PPanel = true
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
            showMapPanel = true
        }
    }

    func checkSessionGridWarnings() {
        let qsosWithGrid = sessionQSOs.filter {
            $0.theirGrid != nil && !$0.theirGrid!.isEmpty
        }

        if !sessionQSOs.isEmpty, qsosWithGrid.isEmpty {
            ToastManager.shared.warning(
                "No QSOs have grids - add QRZ Callbook in Settings \u{2192} Data"
            )
        } else if sessionQSOs.count > qsosWithGrid.count {
            let missing = sessionQSOs.count - qsosWithGrid.count
            ToastManager.shared.info(
                "\(missing) QSO\(missing == 1 ? "" : "s") missing grid"
            )
        }
    }

    func executeNoteCommand(_ text: String) {
        sessionManager?.appendNote(text)
        ToastManager.shared.commandExecuted("NOTE", result: "Added to session log")
    }

    // MARK: - Spot Posting

    func postSpot(comment: String? = nil) async {
        guard let session = sessionManager?.activeSession,
              session.isPOTA,
              let parkRef = session.parkReference,
              let freq = session.frequency
        else {
            ToastManager.shared.error("SPOT requires active POTA session with frequency")
            return
        }

        let callsign = session.myCallsign
        guard !callsign.isEmpty else {
            ToastManager.shared.error("No callsign configured")
            return
        }

        // Post spot for each park in multi-park activation
        let parks = ParkReference.split(parkRef)
        let potaClient = POTAClient(authService: POTAAuthService())
        var successCount = 0

        for park in parks {
            do {
                let success = try await potaClient.postSpot(
                    callsign: callsign,
                    reference: park,
                    frequency: freq * 1_000,
                    mode: session.mode,
                    comments: comment
                )
                if success {
                    successCount += 1
                }
            } catch {
                ToastManager.shared.error(
                    "Spot failed for \(park): \(error.localizedDescription)"
                )
            }
        }

        if successCount > 0 {
            let label = parks.count > 1
                ? "\(parks.count) parks" : parks.first ?? parkRef
            if let comment, !comment.isEmpty {
                ToastManager.shared.spotPosted(park: label, comment: comment)
            } else {
                ToastManager.shared.spotPosted(park: label)
            }
        }
    }

    // MARK: - Spot Selection

    /// Shared handler for spot selection from both panels and sidebar
    func handleSpotSelection(_ selection: SpotSelection) {
        guard sessionManager?.activeSession != nil else {
            ToastManager.shared.warning("Start a session first")
            return
        }

        // Save session frequency before tuning to spot
        preSpotFrequency = sessionManager?.activeSession?.frequency

        switch selection {
        case let .pota(spot):
            callsignInput = spot.activator
            if let freqKHz = spot.frequencyKHz {
                let freqMHz = freqKHz / 1_000.0
                _ = sessionManager?.updateFrequency(freqMHz, isTuningToSpot: true)
            }
            var noteParts: [String] = [spot.reference]
            if let loc = spot.locationDesc {
                let state = loc.components(separatedBy: "-").last ?? loc
                noteParts.append(state)
            }
            if let parkName = spot.parkName {
                noteParts.append(parkName)
            }
            notes = noteParts.joined(separator: " - ")
            ToastManager.shared.info("Loaded \(spot.activator)")

        case let .rbn(spot):
            callsignInput = spot.callsign
            _ = sessionManager?.updateFrequency(spot.frequencyMHz, isTuningToSpot: true)
            ToastManager.shared.info("Loaded \(spot.callsign)")

        case let .p2p(opportunity):
            callsignInput = opportunity.callsign
            _ = sessionManager?.updateFrequency(
                opportunity.frequencyMHz, isTuningToSpot: true
            )
            var noteParts: [String] = ["P2P", opportunity.parkRef]
            if let loc = opportunity.locationDesc {
                let state = loc.components(separatedBy: "-").last ?? loc
                noteParts.append(state)
            }
            if let parkName = opportunity.parkName {
                noteParts.append(parkName)
            }
            notes = noteParts.joined(separator: " - ")
            ToastManager.shared.info(
                "P2P: \(opportunity.callsign) @ \(opportunity.parkRef)"
            )
        }
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

        preSpotFrequency = sessionManager?.activeSession?.frequency
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
            BLERadioService.shared.setFrequency(freqMHz)
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
        if let grid = confirmation.grid { theirGrid = grid }
        if let ref = confirmation.ref { theirPark = ref }
        if let comment = confirmation.comment { notes = comment }

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
        quickEntryTokens = []
        ToastManager.shared.info("Spot cancelled")
    }
}

import CarrierWaveCore
import CarrierWaveData
import Foundation

// MARK: - QuickLogSection Populate & Commands

extension QuickLogSection {
    /// Populate form fields from a recalled spot
    func populateFromSpot(_ spot: EnrichedSpot) {
        callsignInput = spot.spot.callsign
        theirPark = spot.spot.parkRef ?? spot.spot.wwffRef ?? ""
        theirState = spot.spot.stateAbbr ?? ""
        theirGrid = ""
        rstSent = ""
        rstReceived = ""
        notes = ""
        showFields = true
        callsignFocused = true
        ToastManager.shared.info("Recalled \(spot.spot.callsign)")
    }

    /// Populate quick entry from a recalled QSO with dupe-differentiating values inline
    func populateFromQSO(_ qso: QSO) {
        var parts = [qso.callsign]
        if let park = qso.theirParkReference, !park.isEmpty {
            parts.append(park)
        }
        parts.append(qso.mode)
        if let freq = qso.frequency {
            parts.append(FrequencyFormatter.format(freq))
        }
        callsignInput = parts.joined(separator: " ")
        currentMode = qso.mode
        showFields = true
        callsignFocused = true
        ToastManager.shared.info("Recalled \(qso.callsign)")
    }

    /// Populate from initial spot info passed directly to the view
    func applyInitialSpot() {
        guard let info = initialSpotInfo,
              let callsign = info["callsign"] as? String
        else {
            return
        }
        var parts = [callsign]
        if let ref = info["ref"] as? String {
            parts.append(ref)
        }
        if let mode = info["mode"] as? String {
            parts.append(mode)
            currentMode = mode
        }
        if let freq = info["frequencyMHz"] as? Double {
            parts.append(FrequencyFormatter.format(freq))
        }
        callsignInput = parts.joined(separator: " ")
        callsignFocused = true
    }

    func executeCommand(_ command: LoggerCommand) {
        switch command {
        case let .frequency(freq):
            currentFrequency = freq
            ToastManager.shared.commandExecuted(
                "FREQ", result: FrequencyFormatter.formatWithUnit(freq)
            )
        case let .mode(newMode):
            currentMode = newMode
            ToastManager.shared.commandExecuted("MODE", result: newMode)
        case .help:
            showHelpSheet = true
        case let .note(text):
            notes = text
            if !showFields {
                showFields = true
            }
            showMoreFields = true
            ToastManager.shared.commandExecuted("NOTE", result: "Added to notes")
        case let .myCall(call):
            onMyCallChanged?(call)
            ToastManager.shared.commandExecuted("MYCALL", result: call)
        case let .sessionMetadata(entry):
            applySessionMetadata(entry)
        case .rbn,
             .solar,
             .weather,
             .map,
             .manual:
            // No session here, but none of these panels needs one — the
            // hosting ActivityLogView owns the overlays (HunterPanelOverlays).
            onPanelCommand?(command)
        case .hunt:
            ToastManager.shared.info("Activator spots are listed below")
        default:
            ToastManager.shared.warning(
                "This command is only available during an activation"
            )
        }
    }

    /// Apply a callsign-less field line ("14.046 CW") to the hunter quick-log
    /// defaults. There's no session here, so only frequency and mode stick;
    /// grid and anything else is called out as ignored.
    func applySessionMetadata(_ entry: SessionMetadataEntry) {
        var applied: [String] = []
        if let freq = entry.frequency {
            currentFrequency = freq
            applied.append(FrequencyFormatter.formatWithUnit(freq))
        }
        if let mode = entry.mode {
            currentMode = mode
            applied.append(mode)
        }
        var ignored = entry.unsupported
        if let grid = entry.grid {
            ignored.insert(grid, at: 0)
        }
        if !applied.isEmpty {
            ToastManager.shared.success(
                "Set for next log entries: \(applied.joined(separator: " · "))"
            )
        }
        if !ignored.isEmpty {
            ToastManager.shared.warning(
                "Can't set here: \(ignored.joined(separator: ", "))"
            )
        }
    }

    func effectiveRST(_ value: String) -> String {
        value.isEmpty ? defaultRST : value
    }

    func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed.uppercased()
    }
}

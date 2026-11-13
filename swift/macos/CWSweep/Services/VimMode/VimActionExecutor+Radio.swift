// MARK: - Radio

extension VimActionExecutor {
    func executeTune() -> String? {
        guard selectionState.selectedSpot != nil else {
            return "No spot selected"
        }
        selectionState.vimTuneRequest = true
        return nil
    }

    func executeEnterEntry() -> String? {
        guard let spot = selectionState.selectedSpot else {
            return nil // blank entry
        }
        let freq = spot.spot.frequencyMHz
        let spotMode = spot.spot.mode
        let freqStr = String(format: "%.3f", freq)
        selectionState.pendingSpotEntry = spotMode.isEmpty
            ? "\(spot.spot.callsign) \(freqStr)"
            : "\(spot.spot.callsign) \(freqStr) \(spotMode)"
        return spot.spot.callsign
    }

    func executeEnterBlankEntry() -> String? {
        selectionState.pendingSpotEntry = ""
        return "-- ENTRY --"
    }

    func executeDismiss() -> String? {
        // Dismiss selected spot from view, or delete selected QSO from log
        if selectionState.focusedPane == .spotList {
            guard let spot = selectionState.selectedSpot else {
                return "No spot selected"
            }
            selectionState.vimDismissSpot = true
            return "Dismissed \(spot.spot.callsign)"
        } else if selectionState.focusedPane == .qsoLog {
            selectionState.vimDeleteQSO = true
            return "Deleted QSO"
        }
        return nil
    }

    func executeEditQSO() -> String? {
        guard let qsoId = selectionState.selectedQSOId else {
            return "No QSO selected"
        }
        selectionState.editingQSOId = qsoId
        return "-- EDIT --"
    }

    func executeOpenInspector() -> String? {
        selectionState.vimToggleInspector = true
        return "Inspector"
    }

    func executeLookup() -> String? {
        guard let spot = selectionState.selectedSpot else {
            return "No spot selected"
        }
        return "Lookup \(spot.spot.callsign)"
    }
}

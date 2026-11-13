import CarrierWaveData
import SwiftUI

// MARK: - SessionStartSheet Template Actions

extension SessionStartSheet {
    func loadDefaults() {
        guard !hasLoadedDefaults else {
            return
        }
        hasLoadedDefaults = true
        // The session's callsign is baked immutably into every QSO and ADIF
        // export it produces, so capture it from the canonical profile rather
        // than the `loggerDefaultCallsign` cache. The cache is reconciled on
        // activation (UserProfileService.reconcileCallsignStores), but a value
        // corrected mid-session shouldn't have to wait for a background/foreground
        // cycle before a new session picks it up. Also heals the cache
        // write-through so @AppStorage readers see the correction (CAR-287).
        if let canonical = UserProfileService.shared.getProfile()?.callsign
            .uppercased().trimmingCharacters(in: .whitespaces),
            !canonical.isEmpty, canonical != defaultCallsign
        {
            defaultCallsign = canonical
        }
        selectedMode = defaultMode
        if powerText.isEmpty, !defaultPower.isEmpty {
            powerText = defaultPower
        }
        if selectedRadio == nil, !defaultRadio.isEmpty {
            selectedRadio = defaultRadio
        }
        if selectedAntenna == nil, !defaultAntenna.isEmpty {
            selectedAntenna = defaultAntenna
        }
        if selectedKey == nil, !defaultKey.isEmpty {
            selectedKey = defaultKey
        }
        if selectedMic == nil, !defaultMic.isEmpty {
            selectedMic = defaultMic
        }
        loadSavedPrograms()
        loadConnectorProfiles()
        if !defaultParkReference.isEmpty {
            parkReference = defaultParkReference
        }
        if let tpl = initialTemplate {
            applyTemplate(tpl)
        }
        if let programs = initialPrograms {
            selectedPrograms = programs
        }
        if let park = initialParkReference {
            parkReference = park
        }
        if let summit = initialSotaReference {
            sotaReference = summit
        }
        primeGridFromLocation()
    }

    /// Grid lifecycle on session start:
    /// 1. Always start location service so portable ops get the live grid,
    ///    not a stale home-QTH default.
    /// 2. If GPS already has a fix, use it.
    /// 3. Otherwise fall back to defaultGrid so the field isn't blank while
    ///    GPS warms up — and the onChange handler in the body will overwrite
    ///    it once GPS arrives (unless the user manually typed).
    private func primeGridFromLocation() {
        if let gpsGrid = sessionManager?.locationService.currentGrid {
            myGrid = gpsGrid
        } else if myGrid.isEmpty, !defaultGrid.isEmpty {
            myGrid = defaultGrid
        }
        if sessionManager?.locationService.isMonitoring != true {
            sessionManager?.locationService.start()
            startedLocationForPreFill = true
        }
    }

    /// Apply an initial template's equipment to the current session. Loadouts
    /// are equipment-only (radio/antenna/key/mic) — mode, callsign, programs,
    /// references, etc. stay whatever the operator already chose. This
    /// intentionally ignores non-equipment fields on the template. Used only
    /// for the externally-supplied `initialTemplate` prefill; live loadouts are
    /// Rust-backed (`SessionStartSheet+Loadouts.swift`).
    func applyTemplate(_ tpl: SavedSessionTemplate) {
        applyTemplateEquipment(tpl)
    }

    // MARK: - Private Helpers

    private func applyTemplateEquipment(_ tpl: SavedSessionTemplate) {
        if let radio = tpl.radio {
            selectedRadio = radio
        }
        if let antenna = tpl.antenna {
            selectedAntenna = antenna
        }
        if let key = tpl.key {
            selectedKey = key
        }
        if let mic = tpl.mic {
            selectedMic = mic
        }
    }

    func loadSavedPrograms() {
        if !defaultPrograms.isEmpty,
           let data = defaultPrograms.data(using: .utf8),
           let slugs = try? JSONDecoder().decode([String].self, from: data)
        {
            selectedPrograms = Set(slugs)
        } else {
            // Migration: load from old defaultActivationType
            let oldDefault = UserDefaults.standard.string(
                forKey: "loggerDefaultActivationType"
            ) ?? "casual"
            if oldDefault == "pota" {
                selectedPrograms = ["pota"]
            } else if oldDefault == "sota" {
                selectedPrograms = ["sota"]
            } else {
                selectedPrograms = []
            }
        }
    }
}

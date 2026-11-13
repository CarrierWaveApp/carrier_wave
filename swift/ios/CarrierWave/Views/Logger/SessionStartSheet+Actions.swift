import CarrierWaveData
import SwiftUI

// MARK: - SessionStartSheet Start Action

extension SessionStartSheet {
    func startSession() {
        let trimmedNotes = sessionNotes.trimmingCharacters(in: .whitespaces)

        // Session assembly (callsign construction, activation-type derivation,
        // reference conditioning, mode-gated gear, operator normalization) is now
        // owned by the shared Rust `SessionWizardApi`; the in-Swift path below is
        // the byte-for-byte fallback (and parity reference) used only when the
        // Rust store is momentarily unavailable. Assembly reads the actor-isolated
        // store, so it runs in a `@MainActor` task; the brief hop is invisible.
        Task { @MainActor in
            if let assembled = await rustAssembledSession() {
                startSession(fromRust: assembled)
            } else {
                startSessionInSwift()
            }

            if !trimmedNotes.isEmpty {
                sessionManager?.appendNote(trimmedNotes)
            }

            onSessionStarted?()
            onDismiss()
        }
    }

    /// The original in-Swift assembly. Retained as the fallback + the parity
    /// reference the Rust `assemble_session` port is tested against.
    private func startSessionInSwift() {
        let trimmedAttendees = attendeesText.trimmingCharacters(in: .whitespaces)
        let trimmedMission = missionReference.trimmingCharacters(in: .whitespaces)
        let trimmedWwff = wwffReference.trimmingCharacters(in: .whitespaces)

        sessionManager?.startSession(
            myCallsign: fullCallsign,
            mode: selectedMode,
            frequency: parsedFrequency,
            programs: selectedPrograms,
            activationType: ActivationType.from(programs: selectedPrograms),
            parkReference: selectedPrograms.contains("pota") ? parkReference.uppercased() : nil,
            sotaReference: selectedPrograms.contains("sota") ? sotaReference.uppercased() : nil,
            missionReference: selectedPrograms.contains("aoa") && !trimmedMission.isEmpty ? trimmedMission : nil,
            wwffReference: selectedPrograms.contains("wwff") && !trimmedWwff.isEmpty ? trimmedWwff.uppercased() : nil,
            myGrid: myGrid.isEmpty ? nil : myGrid.uppercased(),
            power: parsedPower,
            myRig: selectedRadio,
            myAntenna: selectedAntenna,
            myKey: selectedMode == "CW" ? selectedKey : nil,
            myMic: ["SSB", "USB", "LSB", "AM", "FM"].contains(selectedMode) ? selectedMic : nil,
            extraEquipment: nil,
            attendees: trimmedAttendees.isEmpty ? nil : trimmedAttendees,
            isRove: isRove,
            autoStartSDR: sdrAutoStart && !sdrLastReceiverHostPort.isEmpty,
            contestId: selectedContest?.id,
            contestCategory: selectedContest != nil ? contestCategory : nil,
            contestOverlayCategory: selectedContest != nil && !contestOverlayCategory.isEmpty
                ? contestOverlayCategory
                : nil,
            contestPower: selectedContest != nil ? contestPowerClass : nil,
            contestBands: selectedContest != nil ? contestBands : nil,
            stationCallsign: clubStationCallsign,
            operatorCallsigns: additionalOperators,
            totaOptions: selectedPrograms.contains("tota") ? totaSessionOptions : nil,
            radioItemID: selectedRadioItemID
        )
    }
}

import CarrierWaveCore
import CarrierWaveData
import UIKit

// MARK: - SessionStartSheet Rust-backed assembly

/// Routes the wizard's session assembly through the shared Rust
/// `SessionWizardApi` (the same kernel the Android wizard uses), so callsign
/// construction, activation-type derivation, reference conditioning, mode-gated
/// gear, and operator normalization have a single cross-platform source of
/// truth. Only the pure assembly moves; grid cache/GPS resolution, rove seeding,
/// TOTA options, and every session side effect stay in `LoggingSessionManager`.
extension SessionStartSheet {
    /// Assemble the session from the current wizard state via Rust. Returns `nil`
    /// when the encrypted store can't be opened, so the caller can fall back to
    /// the in-Swift path (session start must never be blocked on the store).
    func rustAssembledSession() async -> FfiLoggingSession? {
        guard let store = try? await CwStoreProvider.shared.store() else {
            return nil
        }
        return SessionWizardApi(store: store).assembleSession(input: makeCreateSessionInput())
    }

    /// Build the shared-Rust wizard input from raw wizard state. References are
    /// passed unconditioned — Rust drops the ones whose program isn't selected
    /// and applies the per-reference normalization. Frequency/power stay
    /// host-parsed this phase. TOTA options continue through the manager, so
    /// `tota` is left `nil` here.
    func makeCreateSessionInput() -> FfiCreateSessionInput {
        FfiCreateSessionInput(
            baseCallsign: defaultCallsign,
            callsignPrefix: callsignPrefix,
            suffix: effectiveSuffix,
            isClubStation: isClubStation,
            clubCallsignInput: clubCallsignInput,
            mode: selectedMode,
            frequencyMhz: parsedFrequency,
            programs: Array(selectedPrograms),
            parkReference: parkReference.isEmpty ? nil : parkReference,
            sotaReference: sotaReference.isEmpty ? nil : sotaReference,
            missionReference: missionReference.isEmpty ? nil : missionReference,
            wwffReference: wwffReference.isEmpty ? nil : wwffReference,
            myGrid: myGrid.isEmpty ? nil : myGrid,
            power: parsedPower.map(Int64.init),
            myRig: selectedRadio,
            myAntenna: selectedAntenna,
            selectedKey: selectedKey,
            selectedMic: selectedMic,
            extraEquipment: nil,
            attendees: attendeesText,
            isRove: isRove,
            contestId: nil,
            contestCategory: nil,
            contestOverlayCategory: nil,
            contestPower: nil,
            contestBands: nil,
            contestOperator: nil,
            operatorCallsigns: additionalOperators,
            // cw-store ids are lowercase; Swift `.uuidString` is uppercase.
            radioItemId: selectedRadioItemID?.uuidString.lowercased()
        )
    }

    /// Start the session from Rust-assembled values: callsign / activation type /
    /// references / grid / gear-gating / station / operators come from `session`;
    /// everything the manager still owns (power, frequency, rig, contest, TOTA,
    /// rove, SDR, radio item) is sourced from state as before.
    func startSession(fromRust session: FfiLoggingSession) {
        let activation = ActivationType(rawValue: session.activationTypeRawValue) ?? .casual
        let operators = (try? JSONDecoder().decode(
            [String].self,
            from: Data(session.operatorCallsignsRawValue.utf8)
        )) ?? additionalOperators

        sessionManager?.startSession(
            myCallsign: session.myCallsign,
            mode: selectedMode,
            frequency: parsedFrequency,
            programs: selectedPrograms,
            activationType: activation,
            parkReference: session.parkReference,
            sotaReference: session.sotaReference,
            missionReference: session.missionReference,
            wwffReference: session.wwffReference,
            myGrid: session.myGrid,
            power: parsedPower,
            myRig: selectedRadio,
            myAntenna: selectedAntenna,
            myKey: session.myKey,
            myMic: session.myMic,
            extraEquipment: nil,
            attendees: session.attendees,
            isRove: isRove,
            autoStartSDR: sdrAutoStart && !sdrLastReceiverHostPort.isEmpty,
            contestId: selectedContest?.id,
            contestCategory: selectedContest != nil ? contestCategory : nil,
            contestOverlayCategory: selectedContest != nil && !contestOverlayCategory.isEmpty
                ? contestOverlayCategory
                : nil,
            contestPower: selectedContest != nil ? contestPowerClass : nil,
            contestBands: selectedContest != nil ? contestBands : nil,
            stationCallsign: session.stationCallsign,
            operatorCallsigns: operators,
            totaOptions: selectedPrograms.contains("tota") ? totaSessionOptions : nil,
            radioItemID: selectedRadioItemID
        )
    }
}

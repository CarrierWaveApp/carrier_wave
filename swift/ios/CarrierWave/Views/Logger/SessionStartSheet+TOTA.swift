// TOTA-specific bits of `SessionStartSheet` lifted into their own extension
// so the main file stays under SwiftLint's 500-line cap. Behavioural code only
// — bindings, `@State`, and the body live in the parent.

import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

extension SessionStartSheet {
    /// QRP for TOTA scoring is fully derived from the wattage field — we don't
    /// expose a manual toggle. Threshold matches TOTA's published rule (≤ 10 W).
    /// Empty / unparseable wattage means "we don't know", so we don't claim QRP.
    var totaQRP: Bool {
        guard let watts = parsedPower else {
            return false
        }
        return watts <= 10
    }

    /// Try to fill `totaRuckWeightPounds` by summing weights of selected gear.
    /// Only writes when the user hasn't already entered a manual value (the
    /// auto-fill flag is cleared if they edit the field by hand). Catalog
    /// look-ups match by `displayName`/`fullDisplayName` since the SessionStart
    /// pickers store raw strings, not EquipmentItem ids.
    func recomputeTOTARuckWeightIfNeeded() {
        guard selectedPrograms.contains("tota") else {
            return
        }
        if let existing = totaRuckWeightPounds, existing > 0, !totaRuckWeightAutoFilled {
            return
        }
        let names = [selectedRadio, selectedAntenna, selectedKey, selectedMic].compactMap { $0 }
        guard !names.isEmpty else {
            clearTOTARuckAutoFill()
            return
        }
        let descriptor = FetchDescriptor<EquipmentItem>()
        guard let items = try? modelContext.fetch(descriptor) else {
            return
        }
        let matched = items.filter { item in
            names.contains(item.displayName) || names.contains(item.fullDisplayName)
        }
        let totalOunces = matched.compactMap(\.weightOunces).reduce(0, +)
        if totalOunces > 0 {
            // Round to 0.1 lb so the field stays tidy.
            totaRuckWeightPounds = (Double(totalOunces) / 1.6).rounded() / 10.0
            totaRuckWeightAutoFilled = true
        } else {
            clearTOTARuckAutoFill()
        }
    }

    var totaSessionOptions: TOTASessionOptions {
        TOTASessionOptions(
            activationLatitude: totaActivationLatitude,
            activationLongitude: totaActivationLongitude,
            recordTrack: totaRecordTrack,
            qrpActivation: totaQRP,
            withPets: totaWithPets,
            withKids: totaWithKids,
            winlinkSent: totaWinlinkSent,
            aprsSent: totaAprsSent,
            varacSent: totaVaracSent,
            adaptiveSport: totaAdaptiveSport,
            ruckWeightPounds: totaRuckWeightPounds,
            category: totaCategory,
            personalEffortFactor: totaPersonalEffortFactor > 0 ? totaPersonalEffortFactor : nil,
            winterActivationOverride: totaWinterOverride
        )
    }

    /// Auto-detected winter flag using the activation coordinate (defaults to
    /// northern hemisphere when no coord set yet).
    var totaAutoDetectedWinter: Bool {
        TOTAWinterDetector.isWinter(
            latitude: totaActivationLatitude,
            date: Date()
        )
    }

    /// Effective winter flag — operator's override if set, else the auto-detect.
    var totaEffectiveWinter: Bool {
        totaWinterOverride ?? totaAutoDetectedWinter
    }

    /// Copy the profile-level PEF onto the session at sheet open. Idempotent —
    /// only fires when the local state is the sentinel zero.
    func loadTOTAProfileDefaultsIfNeeded() {
        if totaPersonalEffortFactor == 0 {
            totaPersonalEffortFactor = totaProfilePEF
        }
    }

    private func clearTOTARuckAutoFill() {
        if totaRuckWeightAutoFilled {
            totaRuckWeightPounds = nil
            totaRuckWeightAutoFilled = false
        }
    }
}

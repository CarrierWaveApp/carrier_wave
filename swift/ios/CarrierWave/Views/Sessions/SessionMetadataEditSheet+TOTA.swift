// TOTA edit section for SessionMetadataEditSheet.
//
// Lifted into its own extension to keep the parent file under SwiftLint's
// type-body cap. Per docs/features/tota-scoring.md the editable fields are
// pre-upload only — once `totaOfficialPoints` is non-nil, the controls disable
// and a "Locked: submitted to TOTA" notice appears. PEF is frozen at session
// start (rules requirement) and is read-only here.

import CarrierWaveCore
import CarrierWaveData
import SwiftUI

extension SessionMetadataEditSheet {
    @ViewBuilder
    var totaSection: some View {
        if session.activationType == .tota {
            Section {
                if session.totaOfficialPoints != nil {
                    submittedNotice
                }
                categoryPicker
                distanceField
                elevationField
                ruckField
                winterToggle
                firstEverToggle
                bonusToggles
                if let pef = session.personalEffortFactor {
                    pefBadgeRow(pef: pef)
                }
            } header: {
                Text("TOTA")
            } footer: {
                if session.totaOfficialPoints == nil {
                    Text(
                        "Edit pre-upload inputs. PEF is frozen at session start "
                            + "per the rules. After upload, all fields lock."
                    )
                } else {
                    Text("This activation has been submitted; inputs are locked.")
                }
            }
        }
    }

    // MARK: Private — UI

    private var locked: Bool {
        session.totaOfficialPoints != nil
    }

    private var submittedNotice: some View {
        Label("Locked: submitted to TOTA", systemImage: "lock.fill")
            .font(.caption)
            .foregroundStyle(.orange)
    }

    private var categoryPicker: some View {
        Picker("Category", selection: categoryBinding) {
            ForEach(TOTACategory.allCases, id: \.self) { value in
                Label(value.displayName, systemImage: value.icon).tag(value)
            }
        }
        .pickerStyle(.segmented)
        .disabled(locked)
    }

    private var distanceField: some View {
        HStack {
            Label("Distance", systemImage: "ruler")
            Spacer()
            TextField("miles", text: distanceText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .disabled(locked)
            Text("mi")
                .foregroundStyle(.secondary)
        }
    }

    private var elevationField: some View {
        HStack {
            Label("Elevation gain", systemImage: "mountain.2")
            Spacer()
            TextField("feet", text: elevationText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .disabled(locked)
            Text("ft")
                .foregroundStyle(.secondary)
        }
    }

    private var ruckField: some View {
        HStack {
            Label("Ruck weight", systemImage: "backpack")
            Spacer()
            TextField("lbs", text: ruckText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .disabled(locked)
            Text("lb")
                .foregroundStyle(.secondary)
        }
    }

    private var winterToggle: some View {
        Toggle(isOn: winterBinding) {
            Label("Winter activation (+20%)", systemImage: "snowflake")
        }
        .disabled(locked)
    }

    private var firstEverToggle: some View {
        Toggle(isOn: firstEverBinding) {
            VStack(alignment: .leading, spacing: 2) {
                Text("First activation of this tile, ever (+10)")
                Text("Server confirms; uncheck if unsure.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(locked)
    }

    private var bonusToggles: some View {
        Group {
            Toggle("With pets (+15%)", isOn: petsBinding).disabled(locked)
            Toggle("With kids (+20%)", isOn: kidsBinding).disabled(locked)
            Toggle("Winlink RF sent (+5)", isOn: winlinkBinding).disabled(locked)
            Toggle("APRS RF sent (+5)", isOn: aprsBinding).disabled(locked)
            Toggle("VarAC RF sent (+5)", isOn: varacBinding).disabled(locked)
            Toggle("Adaptive sport", isOn: adaptiveBinding).disabled(locked)
        }
    }

    private func pefBadgeRow(pef: Int) -> some View {
        HStack {
            Label("Personal Effort Factor", systemImage: "figure.walk.motion")
            Spacer()
            Text("PEF \(pef) (frozen)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Private — Bindings

    private var categoryBinding: Binding<TOTACategory> {
        Binding(
            get: { session.totaCategory },
            set: { session.totaCategory = $0 }
        )
    }

    private var distanceText: Binding<String> {
        Binding(
            get: { session.activationDistanceMiles.map { String(format: "%.2f", $0) } ?? "" },
            set: { session.activationDistanceMiles = Double($0) }
        )
    }

    private var elevationText: Binding<String> {
        Binding(
            get: { session.activationElevationGainFeet.map { String(Int($0)) } ?? "" },
            set: { session.activationElevationGainFeet = Double($0) }
        )
    }

    private var ruckText: Binding<String> {
        Binding(
            get: { session.ruckWeightPounds.map { String(format: "%.1f", $0) } ?? "" },
            set: { session.ruckWeightPounds = Double($0) }
        )
    }

    private var winterBinding: Binding<Bool> {
        Binding(
            get: {
                session.winterActivationOverride
                    ?? TOTAWinterDetector.isWinter(
                        latitude: session.activationLatitude,
                        date: session.startedAt
                    )
            },
            set: { session.winterActivationOverride = $0 }
        )
    }

    private var firstEverBinding: Binding<Bool> {
        Binding(
            get: { session.firstActivationOfTileEver },
            set: { session.firstActivationOfTileEver = $0 }
        )
    }

    private var petsBinding: Binding<Bool> {
        Binding(get: { session.withPets }, set: { session.withPets = $0 })
    }

    private var kidsBinding: Binding<Bool> {
        Binding(get: { session.withKids }, set: { session.withKids = $0 })
    }

    private var winlinkBinding: Binding<Bool> {
        Binding(get: { session.winlinkSent }, set: { session.winlinkSent = $0 })
    }

    private var aprsBinding: Binding<Bool> {
        Binding(get: { session.aprsSent }, set: { session.aprsSent = $0 })
    }

    private var varacBinding: Binding<Bool> {
        Binding(get: { session.varacSent }, set: { session.varacSent = $0 })
    }

    private var adaptiveBinding: Binding<Bool> {
        Binding(get: { session.adaptiveSport }, set: { session.adaptiveSport = $0 })
    }
}

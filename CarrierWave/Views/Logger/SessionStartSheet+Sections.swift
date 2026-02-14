import CarrierWaveCore
import SwiftUI

// MARK: - SessionStartSheet Section Views

extension SessionStartSheet {
    var callsignSection: some View {
        Section {
            callsignDisplayView
            callsignPrefixRow
            suffixPicker
            customSuffixRow
            gridRow
        } header: {
            Text("Station")
        } footer: {
            callsignFooter
        }
    }

    @ViewBuilder
    var callsignDisplayView: some View {
        if !defaultCallsign.isEmpty {
            VStack(spacing: 8) {
                Text(fullCallsign)
                    .font(.title2.monospaced().bold())
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)

                if !callsignPrefix.isEmpty || selectedSuffix != .none {
                    CallsignBreakdownView(
                        prefix: callsignPrefix,
                        baseCallsign: defaultCallsign,
                        suffix: effectiveSuffix
                    )
                }
            }
        }
    }

    var callsignPrefixRow: some View {
        HStack {
            Text("Prefix")
                .foregroundStyle(.secondary)
            Spacer()
            TextField("e.g. I, VE", text: $callsignPrefix)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .multilineTextAlignment(.trailing)
                .font(.subheadline.monospaced())
                .frame(width: 80)
        }
    }

    var suffixPicker: some View {
        Picker("Suffix", selection: $selectedSuffix) {
            ForEach(CallsignSuffix.allCases) { suffix in
                Text(suffix.rawValue).tag(suffix)
            }
        }
    }

    @ViewBuilder
    var customSuffixRow: some View {
        if selectedSuffix == .custom {
            HStack {
                Text("Custom Suffix")
                    .foregroundStyle(.secondary)
                Spacer()
                TextField("e.g. 1, 2, QRP", text: $customSuffix)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
                    .font(.subheadline.monospaced())
                    .frame(width: 100)
            }
        }
    }

    @ViewBuilder
    var gridRow: some View {
        if !defaultGrid.isEmpty || !myGrid.isEmpty {
            HStack {
                Text("Grid")
                    .foregroundStyle(.secondary)
                Spacer()
                TextField("FN31", text: $myGrid)
                    .textInputAutocapitalization(.characters)
                    .multilineTextAlignment(.trailing)
                    .font(.subheadline.monospaced())
            }
        }
    }

    @ViewBuilder
    var callsignFooter: some View {
        if defaultCallsign.isEmpty {
            Text("Set your callsign in Settings → About Me")
        } else if !callsignPrefix.isEmpty {
            Text(
                "Prefix indicates operating from another location (e.g., I/W6JSV for W6JSV in Italy)"
            )
        }
    }

    func frequencyOptionalCallout(for type: ActivationType) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.blue)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text("Frequency is optional")
                    .font(.subheadline.weight(.semibold))
                Text(
                    "Start without a frequency to hunt other activators first."
                        + " Use the BAND command to pick your run frequency"
                        + " when you're ready. Until then, QSOs log without a band."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    var activationSection: some View {
        ActivationSectionView(
            activationType: $activationType,
            parkReference: $parkReference,
            sotaReference: $sotaReference,
            userGrid: myGrid.isEmpty ? defaultGrid : myGrid,
            defaultCountry: "US"
        )
    }
}

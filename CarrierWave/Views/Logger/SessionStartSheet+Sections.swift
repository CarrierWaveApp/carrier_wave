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

    var powerSection: some View {
        Section {
            HStack {
                TextField("100", text: $powerText)
                    .keyboardType(.numberPad)
                    .font(.title3.monospaced())

                Text("W")
                    .foregroundStyle(.secondary)
            }

            if let warning = powerWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Power")
        } footer: {
            Text("Transmit power in watts (optional). US max is 1,500W.")
        }
    }

    var radioSection: some View {
        Section {
            Button {
                showRadioPicker = true
            } label: {
                HStack {
                    Label(
                        selectedRadio ?? "None",
                        systemImage: "radio"
                    )
                    .foregroundStyle(selectedRadio != nil ? .primary : .secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        } header: {
            Text("Radio")
        } footer: {
            Text("Your radio for this session (optional)")
        }
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

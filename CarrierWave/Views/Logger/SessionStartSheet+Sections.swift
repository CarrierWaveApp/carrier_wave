import CarrierWaveCore
import SwiftUI

// MARK: - SessionStartSheet Section Views

extension SessionStartSheet {
    var callsignSection: some View {
        Section {
            callsignDisplayView
            prefixSuffixGroup
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
            Text(fullCallsign)
                .font(.title2.monospaced().bold())
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowSeparator(.hidden)
        }
    }

    var prefixSuffixGroup: some View {
        DisclosureGroup(
            "Prefix / Suffix",
            isExpanded: $showPrefixSuffix
        ) {
            callsignPrefixRow
            suffixPicker
            customSuffixRow
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

    func frequencyOptionalCallout() -> some View {
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
            selectedPrograms: $selectedPrograms,
            parkReference: $parkReference,
            sotaReference: $sotaReference,
            missionReference: $missionReference,
            isRove: $isRove,
            userGrid: myGrid.isEmpty ? defaultGrid : myGrid,
            defaultCountry: "US"
        )
    }

    var modeSection: some View {
        Section("Mode") {
            Picker("Mode", selection: $selectedMode) {
                ForEach(["CW", "SSB", "FT8", "FT4", "RTTY", "AM", "FM"], id: \.self) { mode in
                    Text(mode).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    var frequencySection: some View {
        Section {
            HStack {
                TextField("14.060", text: $frequency)
                    .keyboardType(.decimalPad)
                    .font(.title3.monospaced())

                Text("MHz")
                    .foregroundStyle(.secondary)
            }

            DisclosureGroup(
                "Band Suggestions",
                isExpanded: $showBandSuggestions
            ) {
                FrequencyBandView(
                    selectedMode: selectedMode,
                    frequency: $frequency,
                    detailBand: $bandDetail
                )
            }

            // Prominent callout for POTA/SOTA when no frequency entered
            if frequency.isEmpty,
               !selectedPrograms.isEmpty
            {
                frequencyOptionalCallout()
            }
        } header: {
            HStack {
                Text("Frequency")
                Spacer()
                Button {
                    showBandPlanSheet = true
                } label: {
                    Label("Band Plan", systemImage: "info.circle")
                        .font(.caption)
                }
            }
        } footer: {
            Text(
                "Enter as MHz (14.060), kHz (14060), or dot-separated (14.030.50)."
                    + " You can also type \"14060 kHz\" or \"14.060 MHz\"."
            )
        }
    }

    var optionsSection: some View {
        Section {
            Button {
                saveDefaults()
            } label: {
                HStack {
                    Label("Save as Defaults", systemImage: "square.and.arrow.down")
                    Spacer()
                    if showSavedConfirmation {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .labelStyle(.iconOnly)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
        } header: {
            Text("Options")
        } footer: {
            Text("Defaults are used when starting a new session")
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

import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - SessionStartSheet Section Views

extension SessionStartSheet {
    // MARK: - Sections

    /// Operator details: club, prefix/suffix. Sits below the hero.
    var callsignSection: some View {
        Section {
            clubStationToggle
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            prefixSuffixGroup
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        } header: {
            Text("Station")
        } footer: {
            callsignFooter
        }
    }

    var clubStationToggle: some View {
        Group {
            Toggle("Operating as club station", isOn: $isClubStation)
                .onChange(of: isClubStation) { _, newValue in
                    if newValue {
                        callsignPrefix = ""
                        selectedSuffix = .none
                        customSuffix = ""
                    } else {
                        clubCallsignInput = ""
                    }
                }
            if isClubStation {
                HStack {
                    Text("Club Call")
                        .foregroundStyle(.secondary)
                    Spacer()
                    TextField("e.g. W1AW", text: $clubCallsignInput)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                        .font(.subheadline.monospaced())
                        .frame(width: 120)
                }
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            }
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
        Button {
            showPrefixPicker = true
        } label: {
            HStack {
                Text("Prefix")
                    .foregroundStyle(.secondary)
                Spacer()
                if callsignPrefix.isEmpty {
                    Text("None")
                        .foregroundStyle(.tertiary)
                } else {
                    Text(callsignPrefix.uppercased())
                        .font(.subheadline.monospaced().bold())
                        .foregroundStyle(.primary)
                    if let country = LocationPrefixLookup.search(callsignPrefix)
                        .first(where: { $0.prefix.uppercased() == callsignPrefix.uppercased() })
                    {
                        Text("(\(country.name))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }

    var suffixPicker: some View {
        Picker("Suffix", selection: $selectedSuffix) {
            ForEach(CallsignSuffix.allCases) { suffix in
                Text(suffix.rawValue).tag(suffix)
            }
        }
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
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
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        }
    }

    @ViewBuilder
    var callsignFooter: some View {
        if isClubStation {
            let call = defaultCallsign.uppercased()
            Text(
                "Your callsign (\(call)) is recorded as operator."
                    + " Auto-uploads are disabled for club sessions."
            )
        } else if !callsignPrefix.isEmpty {
            Text(
                "Prefix indicates operating from another location (e.g., I/W6JSV for W6JSV in Italy)"
            )
        } else if myGrid.isEmpty,
                  sessionManager?.locationService.locationError != nil
        {
            Text("Location unavailable — enter grid manually in the hero above")
        }
    }

    var activationSection: some View {
        ActivationSectionView(
            selectedPrograms: $selectedPrograms,
            parkReference: $parkReference,
            sotaReference: $sotaReference,
            missionReference: $missionReference,
            wwffReference: $wwffReference,
            isRove: $isRove,
            userGrid: myGrid.isEmpty ? defaultGrid : myGrid,
            defaultCountry: "US",
            onParkGridChanged: { grid in
                if let grid, !grid.isEmpty, myGrid.isEmpty {
                    myGrid = grid
                }
            },
            totaActivationLatitude: $totaActivationLatitude,
            totaActivationLongitude: $totaActivationLongitude,
            totaRecordTrack: $totaRecordTrack,
            totaParsedPower: parsedPower,
            totaWithPets: $totaWithPets,
            totaWithKids: $totaWithKids,
            totaWinlinkSent: $totaWinlinkSent,
            totaAprsSent: $totaAprsSent,
            totaVaracSent: $totaVaracSent,
            totaAdaptiveSport: $totaAdaptiveSport,
            totaRuckWeightPounds: $totaRuckWeightPounds,
            totaCategory: $totaCategory,
            totaWinterOverride: $totaWinterOverride,
            totaPersonalEffortFactor: $totaPersonalEffortFactor,
            totaRuckWeightAutoFilled: totaRuckWeightAutoFilled,
            totaAutoDetectedWinter: totaAutoDetectedWinter
        )
    }

    private var isFixedFrequencyMode: Bool {
        ["FT8", "FT4"].contains(selectedMode)
    }

    private var fixedFrequencies: [String: Double] {
        selectedMode == "FT8" ? BandPlan.ft8Frequencies : BandPlan.ft4Frequencies
    }

    private var selectedBandForPills: String? {
        guard let parsed = FrequencyFormatter.parse(frequency) else {
            return nil
        }
        // Match against the fixed frequency map
        for (band, freq) in fixedFrequencies where abs(freq - parsed) < 0.001 {
            return band
        }
        return nil
    }

    /// Mode, frequency, and power share one "Radio" section. Frequency and
    /// power sit side by side in free-form mode (both are short numeric
    /// entries) and stack when FT8/FT4 band pills need the full row width.
    var radioSection: some View {
        Section {
            Picker("Mode", selection: $selectedMode) {
                ForEach(["CW", "SSB", "FT8", "FT4", "RTTY", "AM", "FM"], id: \.self) { mode in
                    Text(mode).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }

            if isFixedFrequencyMode {
                fixedFrequencyPills
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                frequencySuggestionCallout
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            } else {
                FrequencyScopeField(
                    frequency: $frequency,
                    mode: selectedMode,
                    license: userLicenseClass,
                    spots: scopeSpots,
                    autoPicked: !frequencyOverridden
                        && autoFilledFrequency != nil
                        && frequency == autoFilledFrequency,
                    determining: frequencySuggestionLoading
                )
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.subheadline)
                    .foregroundStyle(Color.purple)
                    .accessibilityHidden(true)
                Text("Radio")
                Spacer()
                Button {
                    showBandPlanSheet = true
                } label: {
                    Label("Band Plan", systemImage: "info.circle")
                        .font(.caption)
                }
                .textCase(nil)
            }
        }
        .headerProminence(.increased)
    }

    /// Power lives with the gear (it's a station/equipment parameter, not a
    /// tuning one), rendered as a labelled numeric row in the Gear section.
    var powerRow: some View {
        HStack {
            Text("Power")
                .foregroundStyle(.secondary)
            Spacer()
            TextField("100", text: $powerText)
                .keyboardType(.numberPad)
                .font(.title3.monospaced())
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text("W")
                .foregroundStyle(.secondary)
        }
    }

    private static let bandGridOrder = [
        "160m", "80m", "40m", "30m", "20m", "17m", "15m", "12m", "10m", "6m",
    ]

    private static let bandGridColumns = Array(
        repeating: GridItem(.flexible(), spacing: 6), count: 5
    )

    private var fixedFrequencyPills: some View {
        Group {
            LazyVGrid(columns: Self.bandGridColumns, spacing: 6) {
                ForEach(Self.bandGridOrder, id: \.self) { band in
                    if let freq = fixedFrequencies[band] {
                        bandCell(band: band, frequency: freq)
                    }
                }
            }
            .padding(.vertical, 4)

            if let selected = selectedBandForPills,
               let freq = fixedFrequencies[selected]
            {
                HStack {
                    Spacer()
                    Text(FrequencyFormatter.formatWithUnit(freq))
                        .font(.title3.monospaced().weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
    }

    private func bandCell(band: String, frequency freq: Double) -> some View {
        let isSelected = selectedBandForPills == band
        return Button {
            frequency = FrequencyFormatter.format(freq)
        } label: {
            Text(band)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    isSelected ? Color.accentColor : Color(.secondarySystemFill)
                )
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    /// Save-as-Defaults row, folded into the Notes section (it no longer
    /// warrants its own "Options" section).
    var saveDefaultsRow: some View {
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
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }
}

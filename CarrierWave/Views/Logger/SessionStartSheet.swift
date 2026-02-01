import SwiftUI

// MARK: - SessionStartSheet

/// Session setup wizard for starting a new logging session
struct SessionStartSheet: View {
    // MARK: Internal

    var sessionManager: LoggingSessionManager?
    var onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                callsignSection
                modeSection
                frequencySection
                activationSection
                optionsSection
            }
            .navigationTitle("Start Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        startSession()
                    }
                    .disabled(!canStart)
                }
            }
        }
    }

    // MARK: Private

    @AppStorage("loggerDefaultCallsign") private var defaultCallsign = ""
    @AppStorage("loggerDefaultMode") private var defaultMode = "CW"
    @AppStorage("loggerDefaultGrid") private var defaultGrid = ""
    @AppStorage("loggerDefaultActivationType") private var defaultActivationType = "casual"
    @AppStorage("loggerDefaultParkReference") private var defaultParkReference = ""
    @AppStorage("loggerSkipWizard") private var skipWizard = false

    @State private var selectedMode = "CW"
    @State private var frequency = ""
    @State private var activationType: ActivationType = .casual
    @State private var parkReference = ""
    @State private var sotaReference = ""
    @State private var myGrid = ""

    // Callsign prefix/suffix
    @State private var callsignPrefix = ""
    @State private var selectedSuffix: CallsignSuffix = .none
    @State private var customSuffix = ""

    /// UI state
    @State private var showSavedConfirmation = false

    /// The full constructed callsign (prefix/base/suffix)
    private var fullCallsign: String {
        var parts: [String] = []

        let prefix = callsignPrefix.trimmingCharacters(in: .whitespaces).uppercased()
        if !prefix.isEmpty {
            parts.append(prefix)
        }

        parts.append(defaultCallsign.uppercased())

        let suffix = effectiveSuffix
        if !suffix.isEmpty {
            parts.append(suffix)
        }

        return parts.joined(separator: "/")
    }

    /// The effective suffix based on selection
    private var effectiveSuffix: String {
        switch selectedSuffix {
        case .none:
            ""
        case .portable:
            "P"
        case .mobile:
            "M"
        case .maritime:
            "MM"
        case .aeronautical:
            "AM"
        case .custom:
            customSuffix.trimmingCharacters(in: .whitespaces).uppercased()
        }
    }

    private var canStart: Bool {
        !defaultCallsign.isEmpty && defaultCallsign.count >= 3
    }

    private var parsedFrequency: Double? {
        Double(frequency)
    }

    // MARK: - Sections

    private var callsignSection: some View {
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
        .onAppear {
            if myGrid.isEmpty, !defaultGrid.isEmpty {
                myGrid = defaultGrid
            }
            selectedMode = defaultMode
            if let savedActivationType = ActivationType(rawValue: defaultActivationType) {
                activationType = savedActivationType
            }
            if !defaultParkReference.isEmpty {
                parkReference = defaultParkReference
            }
        }
    }

    @ViewBuilder
    private var callsignDisplayView: some View {
        if !defaultCallsign.isEmpty {
            VStack(spacing: 8) {
                Text(fullCallsign)
                    .font(.title2.monospaced().bold())
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)

                if !callsignPrefix.isEmpty || selectedSuffix != .none {
                    callsignBreakdownView
                }
            }
        }
    }

    private var callsignBreakdownView: some View {
        CallsignBreakdownView(
            prefix: callsignPrefix,
            baseCallsign: defaultCallsign,
            suffix: effectiveSuffix
        )
    }

    private var callsignPrefixRow: some View {
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

    private var suffixPicker: some View {
        Picker("Suffix", selection: $selectedSuffix) {
            ForEach(CallsignSuffix.allCases) { suffix in
                Text(suffix.rawValue).tag(suffix)
            }
        }
    }

    @ViewBuilder
    private var customSuffixRow: some View {
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
    private var gridRow: some View {
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
    private var callsignFooter: some View {
        if defaultCallsign.isEmpty {
            Text("Set your callsign in Settings → About Me")
        } else if !callsignPrefix.isEmpty {
            Text(
                "Prefix indicates operating from another location (e.g., I/W6JSV for W6JSV in Italy)"
            )
        }
    }

    private var modeSection: some View {
        Section("Mode") {
            Picker("Mode", selection: $selectedMode) {
                ForEach(["CW", "SSB", "FT8", "FT4", "RTTY", "AM", "FM"], id: \.self) { mode in
                    Text(mode).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var frequencySection: some View {
        Section {
            HStack {
                TextField("14.060", text: $frequency)
                    .keyboardType(.decimalPad)
                    .font(.title3.monospaced())

                Text("MHz")
                    .foregroundStyle(.secondary)
            }

            frequencySuggestions
        } header: {
            Text("Frequency")
        } footer: {
            Text("Optional - you can change frequency during the session")
        }
    }

    private var frequencySuggestions: some View {
        FrequencySuggestionsView(selectedMode: selectedMode, frequency: $frequency)
    }

    private var activationSection: some View {
        ActivationSectionView(
            activationType: $activationType,
            parkReference: $parkReference,
            sotaReference: $sotaReference,
            userGrid: myGrid.isEmpty ? defaultGrid : myGrid,
            defaultCountry: "US"
        )
    }

    private var optionsSection: some View {
        Section {
            Toggle("Skip wizard next time", isOn: $skipWizard)

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

    private func startSession() {
        sessionManager?.startSession(
            myCallsign: fullCallsign,
            mode: selectedMode,
            frequency: parsedFrequency,
            activationType: activationType,
            parkReference: activationType == .pota ? parkReference.uppercased() : nil,
            sotaReference: activationType == .sota ? sotaReference.uppercased() : nil,
            myGrid: myGrid.isEmpty ? nil : myGrid.uppercased()
        )

        onDismiss()
    }

    private func saveDefaults() {
        defaultMode = selectedMode
        if !myGrid.isEmpty {
            defaultGrid = myGrid.uppercased()
        }
        defaultActivationType = activationType.rawValue
        if activationType == .pota {
            defaultParkReference = parkReference.uppercased()
        } else {
            defaultParkReference = ""
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            showSavedConfirmation = true
        }
    }
}

// MARK: - CallsignBreakdownView

/// Extracted view showing callsign prefix/base/suffix breakdown
struct CallsignBreakdownView: View {
    let prefix: String
    let baseCallsign: String
    let suffix: String

    var body: some View {
        HStack(spacing: 4) {
            if !prefix.isEmpty {
                Text(prefix.uppercased())
                    .font(.caption.monospaced())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.2))
                    .clipShape(Capsule())
                Text("/")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(baseCallsign.uppercased())
                .font(.caption.monospaced())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.2))
                .clipShape(Capsule())

            if !suffix.isEmpty {
                Text("/")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(suffix)
                    .font(.caption.monospaced())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.2))
                    .clipShape(Capsule())
            }
        }
    }
}

// MARK: - ActivationSectionView

/// Extracted view for activation type selection
struct ActivationSectionView: View {
    @Binding var activationType: ActivationType
    @Binding var parkReference: String
    @Binding var sotaReference: String

    /// User's grid square for nearby parks
    var userGrid: String?
    /// Default country prefix for park shorthand
    var defaultCountry: String = "US"

    var body: some View {
        Section("Activation Type") {
            Picker("Type", selection: $activationType) {
                ForEach(ActivationType.allCases, id: \.self) { type in
                    Label(type.displayName, systemImage: type.icon)
                        .tag(type)
                }
            }
            .pickerStyle(.segmented)

            if activationType == .pota {
                ParkEntryField(
                    parkReference: $parkReference,
                    label: "Park",
                    placeholder: "1234 or US-1234",
                    userGrid: userGrid,
                    defaultCountry: defaultCountry
                )
            }

            if activationType == .sota {
                HStack {
                    Text("Summit")
                        .foregroundStyle(.secondary)
                    Spacer()
                    TextField("W4C/CM-001", text: $sotaReference)
                        .textInputAutocapitalization(.characters)
                        .multilineTextAlignment(.trailing)
                        .font(.subheadline.monospaced())
                }
            }
        }
    }
}

// MARK: - FrequencySuggestionsView

/// Extracted view for frequency band suggestions
struct FrequencySuggestionsView: View {
    // MARK: Internal

    let selectedMode: String

    @Binding var frequency: String

    var body: some View {
        let suggestions = LoggingSession.suggestedFrequencies(for: selectedMode)
        let availableBands = Self.sortedBands.filter { suggestions[$0] != nil }

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(availableBands, id: \.self) { band in
                    if let freq = suggestions[band] {
                        bandButton(band: band, freq: freq)
                    }
                }
            }
        }
    }

    // MARK: Private

    private static let sortedBands = [
        "160m", "80m", "40m", "30m", "20m", "17m", "15m", "12m", "10m",
    ]

    private func bandButton(band: String, freq: Double) -> some View {
        let freqString = FrequencyFormatter.format(freq)
        let isSelected = frequency == freqString

        return Button {
            frequency = freqString
        } label: {
            VStack(spacing: 2) {
                Text(band)
                    .font(.caption.weight(.medium))
                Text(freqString)
                    .font(.caption2.monospaced())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.2)
                    : Color(.tertiarySystemGroupedBackground)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    SessionStartSheet(
        sessionManager: nil,
        onDismiss: {}
    )
}

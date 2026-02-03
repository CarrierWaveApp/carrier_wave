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
            .safeAreaInset(edge: .bottom) {
                if let reason = startDisabledReason {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                        Text(reason)
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.ultraThinMaterial)
                }
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
        SessionStartValidation.canStart(
            callsign: defaultCallsign,
            activationType: activationType,
            parkReference: parkReference,
            sotaReference: sotaReference,
            frequency: parsedFrequency
        )
    }

    private var startDisabledReason: String? {
        SessionStartValidation.disabledReason(
            callsign: defaultCallsign,
            activationType: activationType,
            parkReference: parkReference,
            sotaReference: sotaReference,
            frequency: parsedFrequency
        )
    }

    private var parsedFrequency: Double? {
        FrequencyFormatter.parse(frequency)
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

            FrequencySuggestionsView(selectedMode: selectedMode, frequency: $frequency)
        } header: {
            Text("Frequency")
        } footer: {
            Text(
                "Enter as MHz (14.060) or kHz (14060). You can also type \"14060 kHz\" or \"14.060 MHz\"."
            )
        }
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

// MARK: - Preview

#Preview {
    SessionStartSheet(
        sessionManager: nil,
        onDismiss: {}
    )
}

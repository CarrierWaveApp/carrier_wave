import CarrierWaveCore
import SwiftUI

// MARK: - SessionStartSheet

/// Session setup wizard for starting a new logging session
struct SessionStartSheet: View {
    // MARK: Internal

    var sessionManager: LoggingSessionManager?
    var onDismiss: () -> Void

    @AppStorage("loggerDefaultCallsign") var defaultCallsign = ""
    @AppStorage("loggerDefaultMode") var defaultMode = "CW"
    @AppStorage("loggerDefaultGrid") var defaultGrid = ""
    @State var selectedMode = "CW"
    @State var frequency = ""
    @State var activationType: ActivationType = .casual
    @State var parkReference = ""
    @State var sotaReference = ""
    @State var myGrid = ""

    // Callsign prefix/suffix
    @State var callsignPrefix = ""
    @State var selectedSuffix: CallsignSuffix = .none
    @State var customSuffix = ""

    /// The full constructed callsign (prefix/base/suffix)
    var fullCallsign: String {
        let prefix = callsignPrefix.trimmingCharacters(in: .whitespaces).uppercased()
        let suffix = effectiveSuffix
        let parts = [prefix, defaultCallsign.uppercased(), suffix].filter { !$0.isEmpty }
        return parts.joined(separator: "/")
    }

    /// The effective suffix based on selection
    var effectiveSuffix: String {
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

    var body: some View {
        NavigationStack {
            Form {
                callsignSection
                modeSection
                frequencySection
                activationSection
                optionsSection
            }
            .task {
                guard !hasLoadedDefaults else {
                    return
                }
                hasLoadedDefaults = true
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
            .sheet(isPresented: $showBandPlanSheet) {
                BandPlanSheet(
                    selectedMode: selectedMode,
                    frequency: $frequency
                )
            }
            .sheet(item: $bandDetail) { band in
                BandActivitySheet(
                    suggestion: band,
                    frequency: $frequency
                )
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

    @AppStorage("loggerDefaultActivationType") private var defaultActivationType = "casual"
    @AppStorage("loggerDefaultParkReference") private var defaultParkReference = ""

    /// UI state
    @State private var showSavedConfirmation = false
    @State private var showBandPlanSheet = false
    @State private var bandDetail: BandSuggestion?
    @State private var hasLoadedDefaults = false

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

            FrequencyBandView(
                selectedMode: selectedMode,
                frequency: $frequency,
                detailBand: $bandDetail
            )
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

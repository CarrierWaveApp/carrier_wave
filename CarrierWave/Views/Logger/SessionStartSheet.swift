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
    @State var isRove = false
    @State var myGrid = ""
    @State var powerText = ""
    @State var selectedRadio: String?

    // Callsign prefix/suffix
    @State var callsignPrefix = ""
    @State var selectedSuffix: CallsignSuffix = .none
    @State var customSuffix = ""

    @State var showRadioPicker = false
    @State var showAntennaPicker = false
    @State var showKeyPicker = false
    @State var showMicPicker = false
    @State var showMoreEquipment = false

    // Equipment
    @State var selectedAntenna: String?
    @State var selectedKey: String?
    @State var selectedMic: String?
    @State var extraEquipmentText = ""
    @State var attendeesText = ""
    @State var sessionNotes = ""

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

    var powerWarning: String? {
        guard !powerText.isEmpty else {
            return nil
        }
        guard let watts = Int(powerText) else {
            return "Enter a whole number"
        }
        if watts <= 0 {
            return "Power must be greater than 0"
        }
        if watts > 1_500 {
            return "US maximum is 1,500W"
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                callsignSection
                modeSection
                frequencySection
                powerSection
                equipmentSection
                activationSection
                attendeesSection
                notesSection
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
                if powerText.isEmpty, !defaultPower.isEmpty {
                    powerText = defaultPower
                }
                if selectedRadio == nil, !defaultRadio.isEmpty {
                    selectedRadio = defaultRadio
                }
                if selectedAntenna == nil, !defaultAntenna.isEmpty {
                    selectedAntenna = defaultAntenna
                }
                if selectedKey == nil, !defaultKey.isEmpty {
                    selectedKey = defaultKey
                }
                if selectedMic == nil, !defaultMic.isEmpty {
                    selectedMic = defaultMic
                }
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
            .sheet(isPresented: $showRadioPicker) {
                RadioPickerSheet(selection: $selectedRadio)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showAntennaPicker) {
                EquipmentPickerSheet(
                    equipmentType: .antenna, selection: $selectedAntenna
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showKeyPicker) {
                EquipmentPickerSheet(
                    equipmentType: .key, selection: $selectedKey
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showMicPicker) {
                EquipmentPickerSheet(
                    equipmentType: .mic, selection: $selectedMic
                )
                .presentationDetents([.medium, .large])
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
    @AppStorage("loggerDefaultPower") private var defaultPower = ""
    @AppStorage("loggerDefaultRadio") private var defaultRadio = ""
    @AppStorage("loggerDefaultAntenna") private var defaultAntenna = ""
    @AppStorage("loggerDefaultKey") private var defaultKey = ""
    @AppStorage("loggerDefaultMic") private var defaultMic = ""

    /// UI state
    @State private var showSavedConfirmation = false
    @State private var showBandPlanSheet = false
    @State private var bandDetail: BandSuggestion?
    @State private var showBandSuggestions = false
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

    private var parsedPower: Int? {
        guard !powerText.isEmpty else {
            return nil
        }
        guard let watts = Int(powerText), watts > 0, watts <= 1_500 else {
            return nil
        }
        return watts
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
               activationType == .pota || activationType == .sota
            {
                frequencyOptionalCallout(for: activationType)
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
}

// MARK: - Actions

extension SessionStartSheet {
    func startSession() {
        let trimmedEquipment = extraEquipmentText.trimmingCharacters(in: .whitespaces)
        let trimmedAttendees = attendeesText.trimmingCharacters(in: .whitespaces)
        let trimmedNotes = sessionNotes.trimmingCharacters(in: .whitespaces)

        sessionManager?.startSession(
            myCallsign: fullCallsign,
            mode: selectedMode,
            frequency: parsedFrequency,
            activationType: activationType,
            parkReference: activationType == .pota ? parkReference.uppercased() : nil,
            sotaReference: activationType == .sota ? sotaReference.uppercased() : nil,
            myGrid: myGrid.isEmpty ? nil : myGrid.uppercased(),
            power: parsedPower,
            myRig: selectedRadio,
            myAntenna: selectedAntenna,
            myKey: selectedMode == "CW" ? selectedKey : nil,
            myMic: ["SSB", "USB", "LSB", "AM", "FM"].contains(selectedMode) ? selectedMic : nil,
            extraEquipment: trimmedEquipment.isEmpty ? nil : trimmedEquipment,
            attendees: trimmedAttendees.isEmpty ? nil : trimmedAttendees,
            isRove: isRove
        )

        // Store initial notes if provided
        if !trimmedNotes.isEmpty {
            sessionManager?.appendNote(trimmedNotes)
        }

        onDismiss()
    }

    func saveDefaults() {
        defaultMode = selectedMode
        defaultPower = powerText
        defaultRadio = selectedRadio ?? ""
        defaultAntenna = selectedAntenna ?? ""
        defaultKey = selectedKey ?? ""
        defaultMic = selectedMic ?? ""
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

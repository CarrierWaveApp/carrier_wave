import CarrierWaveData
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
    @State var selectedPrograms: Set<String> = []
    @State var parkReference = ""
    @State var sotaReference = ""
    @State var missionReference = ""
    @State var wwffReference = ""
    @State var isRove = false
    @State var myGrid = ""
    @State var powerText = ""
    @State var selectedRadio: String?

    // Callsign prefix/suffix
    @State var callsignPrefix = ""
    @State var selectedSuffix: CallsignSuffix = .none
    @State var customSuffix = ""

    @State var showPrefixSuffix = false
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

    @AppStorage("loggerDefaultPrograms") var defaultPrograms = ""
    @AppStorage("loggerDefaultParkReference") var defaultParkReference = ""
    @AppStorage("loggerDefaultPower") var defaultPower = ""
    @AppStorage("loggerDefaultRadio") var defaultRadio = ""
    @AppStorage("loggerDefaultAntenna") var defaultAntenna = ""
    @AppStorage("loggerDefaultKey") var defaultKey = ""
    @AppStorage("loggerDefaultMic") var defaultMic = ""

    // SDR auto-start
    @AppStorage("sdrAutoStart") var sdrAutoStart = false
    @AppStorage("sdrLastReceiverHostPort") var sdrLastReceiverHostPort = ""
    @AppStorage("sdrLastReceiverName") var sdrLastReceiverName = ""
    @State var showSDRPicker = false

    /// UI state
    @State var showSavedConfirmation = false
    @State var showBandPlanSheet = false
    @State var bandDetail: BandSuggestion?
    @State var showBandSuggestions = false

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
                sdrSection
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
                loadSavedPrograms()
                if !defaultParkReference.isEmpty {
                    parkReference = defaultParkReference
                }
            }
            .onChange(of: selectedMode) { oldMode, newMode in
                let ftModes: Set<String> = ["FT8", "FT4"]
                let enteringFT = ftModes.contains(newMode)
                let leavingFT = ftModes.contains(oldMode) && !ftModes.contains(newMode)

                if enteringFT {
                    // Auto-select 20m default if frequency is empty or was a known
                    // band frequency from the previous mode
                    let oldFreqs = LoggingSession.suggestedFrequencies(for: oldMode)
                    let parsed = FrequencyFormatter.parse(frequency)
                    let wasKnown = parsed.flatMap { parsedMHz in
                        oldFreqs.values.first { abs($0 - parsedMHz) < 0.001 }
                    } != nil
                    if frequency.isEmpty || wasKnown {
                        let newFreqs = LoggingSession.suggestedFrequencies(for: newMode)
                        if let defaultFreq = newFreqs["20m"] {
                            frequency = FrequencyFormatter.format(defaultFreq)
                        }
                    }
                } else if leavingFT {
                    // Clear the frequency when leaving FT modes
                    frequency = ""
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
                    onFrequencyPicked: { showBandSuggestions = false },
                    frequency: $frequency
                )
            }
            .sheet(isPresented: $showRadioPicker) {
                RadioPickerSheet(selection: $selectedRadio)
                    .landscapeAdaptiveDetents(portrait: [.medium, .large])
            }
            .sheet(isPresented: $showAntennaPicker) {
                EquipmentPickerSheet(
                    equipmentType: .antenna, selection: $selectedAntenna
                )
                .landscapeAdaptiveDetents(portrait: [.medium, .large])
            }
            .sheet(isPresented: $showKeyPicker) {
                EquipmentPickerSheet(
                    equipmentType: .key, selection: $selectedKey
                )
                .landscapeAdaptiveDetents(portrait: [.medium, .large])
            }
            .sheet(isPresented: $showMicPicker) {
                EquipmentPickerSheet(
                    equipmentType: .mic, selection: $selectedMic
                )
                .landscapeAdaptiveDetents(portrait: [.medium, .large])
            }
            .sheet(isPresented: $showSDRPicker) {
                WebSDRPickerSheet(
                    myGrid: myGrid.isEmpty ? defaultGrid : myGrid,
                    operatingBand: parsedFrequency.flatMap { BandUtilities.deriveBand(from: $0 * 1_000) }
                ) { receiver in
                    sdrLastReceiverHostPort = "\(receiver.host):\(receiver.port)"
                    sdrLastReceiverName = receiver.name
                    sdrAutoStart = true
                    showSDRPicker = false
                }
                .landscapeAdaptiveDetents(portrait: [.medium, .large])
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

    @State private var hasLoadedDefaults = false

    private var validationInput: SessionStartInput {
        SessionStartInput(
            callsign: defaultCallsign,
            programs: selectedPrograms,
            parkReference: parkReference,
            sotaReference: sotaReference,
            missionReference: missionReference,
            wwffReference: wwffReference,
            frequency: parsedFrequency
        )
    }

    private var canStart: Bool {
        SessionStartValidation.canStart(validationInput)
    }

    private var startDisabledReason: String? {
        SessionStartValidation.disabledReason(validationInput)
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
}

// MARK: - Actions

extension SessionStartSheet {
    func startSession() {
        let trimmedEquipment = extraEquipmentText.trimmingCharacters(in: .whitespaces)
        let trimmedAttendees = attendeesText.trimmingCharacters(in: .whitespaces)
        let trimmedNotes = sessionNotes.trimmingCharacters(in: .whitespaces)

        let trimmedMission = missionReference.trimmingCharacters(in: .whitespaces)

        let trimmedWwff = wwffReference.trimmingCharacters(in: .whitespaces)

        sessionManager?.startSession(
            myCallsign: fullCallsign,
            mode: selectedMode,
            frequency: parsedFrequency,
            programs: selectedPrograms,
            activationType: ActivationType.from(programs: selectedPrograms),
            parkReference: selectedPrograms.contains("pota") ? parkReference.uppercased() : nil,
            sotaReference: selectedPrograms.contains("sota") ? sotaReference.uppercased() : nil,
            missionReference: selectedPrograms.contains("aoa") && !trimmedMission.isEmpty ? trimmedMission : nil,
            wwffReference: selectedPrograms.contains("wwff") && !trimmedWwff.isEmpty ? trimmedWwff.uppercased() : nil,
            myGrid: myGrid.isEmpty ? nil : myGrid.uppercased(),
            power: parsedPower,
            myRig: selectedRadio,
            myAntenna: selectedAntenna,
            myKey: selectedMode == "CW" ? selectedKey : nil,
            myMic: ["SSB", "USB", "LSB", "AM", "FM"].contains(selectedMode) ? selectedMic : nil,
            extraEquipment: trimmedEquipment.isEmpty ? nil : trimmedEquipment,
            attendees: trimmedAttendees.isEmpty ? nil : trimmedAttendees,
            isRove: isRove,
            autoStartSDR: sdrAutoStart && !sdrLastReceiverHostPort.isEmpty
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
        // Save programs as JSON array
        let sorted = selectedPrograms.sorted()
        if let data = try? JSONEncoder().encode(sorted) {
            defaultPrograms = String(data: data, encoding: .utf8) ?? ""
        }
        if selectedPrograms.contains("pota") {
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

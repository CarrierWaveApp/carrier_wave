import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - ColdStartView + SetupRow

extension ColdStartView {
    /// The effective suffix based on picker selection
    var effectiveSuffix: String {
        switch selectedSuffix {
        case "none": ""
        case "custom": customSuffix.trimmingCharacters(in: .whitespaces).uppercased()
        default: selectedSuffix
        }
    }

    /// Full callsign including prefix and suffix
    var fullCallsign: String {
        let base = keychainCallsign
        let prefix = callsignPrefix.trimmingCharacters(in: .whitespaces).uppercased()
        let suffix = effectiveSuffix
        let parts = [prefix, base.uppercased(), suffix].filter { !$0.isEmpty }
        return parts.joined(separator: "/")
    }

    /// Callsign from Keychain, falling back to @AppStorage
    var keychainCallsign: String {
        (try? KeychainHelper.shared.readString(for: KeychainHelper.Keys.currentCallsign)) ?? myCallsign
    }

    /// Whether all required fields are filled to start a session
    var canStart: Bool {
        !parkReference.trimmingCharacters(in: .whitespaces).isEmpty
            && fullCallsign.count >= 3
    }

    /// Human-readable reason the start button is disabled, or nil if ready
    var startDisabledReason: String? {
        if parkReference.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Select a park"
        }
        if fullCallsign.count < 3 {
            return "Set callsign in Settings"
        }
        return nil
    }

    // MARK: - Setup Row

    var setupRow: some View {
        HStack(spacing: 12) {
            parkSearchSection
            modeToggles
                .frame(width: 200)
            frequencyLabel
                .frame(width: 120)
            callsignSection
                .frame(width: 140)
            equipmentGearButton
            startButtonSection
                .frame(width: 100)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Park Search

    var parkSearchSection: some View {
        ParkSearchField(
            selectedReference: $parkReference,
            onParkSelected: { _, name, grid in
                parkName = name
                parkGrid = grid
                if myGrid.isEmpty, let grid {
                    myGrid = grid
                }
            }
        )
        .layoutPriority(1.2)
    }

    // MARK: - Mode Toggles

    var modeToggles: some View {
        Picker("", selection: $selectedMode) {
            ForEach(supportedModes, id: \.self) { mode in
                Text(mode).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Frequency Label

    var frequencyLabel: some View {
        VStack(spacing: 2) {
            if let suggestion = currentSuggestion {
                Text(FrequencyFormatter.format(suggestion.frequencyMHz))
                    .font(.system(.body, design: .monospaced).bold())
                    .foregroundStyle(.green)
                Text(selectedBand ?? "Auto")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("No suggestion")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Callsign Section

    var callsignSection: some View {
        VStack(spacing: 4) {
            Text(fullCallsign)
                .font(.system(.body, design: .monospaced).bold())
                .foregroundStyle(.blue)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            callsignEditPopover
        }
    }

    var callsignEditPopover: some View {
        ColdStartPopoverButton(label: "+ prefix/suffix") {
            callsignPopoverContent
        }
    }

    var callsignPopoverContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Prefix", text: $callsignPrefix)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)

            Picker("Suffix", selection: $selectedSuffix) {
                Text("None").tag("none")
                Text("/P (Portable)").tag("P")
                Text("/M (Mobile)").tag("M")
                Text("/MM (Maritime)").tag("MM")
                Text("/AM (Aeronautical)").tag("AM")
                Text("Custom...").tag("custom")
            }
            .frame(width: 180)

            if selectedSuffix == "custom" {
                TextField("Custom suffix", text: $customSuffix)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
        }
        .padding(12)
    }

    // MARK: - Equipment Gear

    var equipmentGearButton: some View {
        Button {
            // Scroll anchor — could be wired to a scroll proxy
        } label: {
            Image(systemName: "gearshape")
                .font(.title3)
        }
        .buttonStyle(.borderless)
        .help("Equipment setup")
    }

    // MARK: - Start Button

    var startButtonSection: some View {
        VStack(spacing: 4) {
            Button("Start \u{25B6}") {
                startSession()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canStart)

            if let reason = startDisabledReason {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Actions

    func startSession() {
        let trimmedNotes = sessionNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAttendees = attendeesText.trimmingCharacters(in: .whitespacesAndNewlines)
        let freq = currentSuggestion?.frequencyMHz

        let session = LoggingSession(
            myCallsign: fullCallsign,
            frequency: freq,
            mode: selectedMode,
            programs: Set(["pota"]),
            activationType: .pota,
            parkReference: parkReference.uppercased(),
            myGrid: myGrid.isEmpty ? nil : myGrid.uppercased(),
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            power: Int(powerText),
            myRig: radioManager.connectedRadioName,
            myAntenna: selectedAntenna,
            myKey: selectedKey,
            myMic: selectedMic,
            attendees: trimmedAttendees.isEmpty ? nil : trimmedAttendees
        )

        setOperatorCallsigns(on: session)
        session.isRove = isRove

        modelContext.insert(session)
        try? CwStoreSeams.save(modelContext, sessions: [session])
        saveDefaults()
        onSessionStarted?(session)
    }

    /// Persist current equipment choices for next time.
    func saveDefaults() {
        if let antenna = selectedAntenna {
            EquipmentStorage.add(antenna, for: .antenna)
            lastAntenna = antenna
        }
        if let key = selectedKey {
            EquipmentStorage.add(key, for: .key)
            lastKey = key
        }
        if let mic = selectedMic {
            EquipmentStorage.add(mic, for: .mic)
            lastMic = mic
        }
        lastSuffix = selectedSuffix
        lastPower = powerText
        lastGrid = myGrid
    }

    // MARK: - Private Helpers

    var supportedModes: [String] {
        ["CW", "SSB", "FT8", "FT4"]
    }

    private func setOperatorCallsigns(on session: LoggingSession) {
        guard !additionalOperators.isEmpty else {
            return
        }
        if let data = try? JSONEncoder().encode(additionalOperators),
           let json = String(data: data, encoding: .utf8)
        {
            session.operatorCallsignsRawValue = json
        }
    }
}

// MARK: - ColdStartPopoverButton

/// Small clickable text that shows a popover on tap.
struct ColdStartPopoverButton<Content: View>: View {
    // MARK: Internal

    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        Button(label) {
            isPresented.toggle()
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(.blue)
        .popover(isPresented: $isPresented) {
            content()
        }
    }

    // MARK: Private

    @State private var isPresented = false
}

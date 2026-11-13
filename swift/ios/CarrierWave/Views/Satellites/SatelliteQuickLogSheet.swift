import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - SatelliteQuickLogSheet

/// Post-LOS quick log: satellite, transmitter, mode, and time are prefilled —
/// the operator only types callsign + grid per contact, matching how satellite
/// QSOs are actually copied (log after LOS from memory/scratch, not live).
/// Every QSO logged here is forced to SAT_NAME + PROP_MODE=SAT.
struct SatelliteQuickLogSheet: View {
    // MARK: Internal

    /// Short OSCAR designator ("AO-91") — becomes ADIF SAT_NAME.
    let satName: String
    let detailName: String?
    let transmitters: [SatNOGSTransmitter]
    /// The just-ended (or in-progress) pass; nil logs an ad-hoc contact at "now".
    let pass: SatellitePass?
    let observerGrid: String?
    /// Fresh pass recording (P3): played back inline, and its tap marks
    /// pre-seed one contact row each at the marked time.
    let recording: SatellitePassRecording?
    let onLogged: (Int) -> Void

    var body: some View {
        NavigationStack {
            Form {
                headerSection
                if let recording {
                    Section("Pass Recording") {
                        SatellitePassPlaybackView(recording: recording)
                    }
                }
                tuningSection
                contactsSection
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("\(satName) Pass Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveTitle) { save() }
                        .disabled(filledRowCount == 0)
                }
            }
            .onAppear { prefill() }
        }
    }

    // MARK: Private

    private struct Row: Identifiable {
        let id = UUID()
        var callsign = ""
        var grid = ""
        var time: Date?
        var showTime = false
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var rows: [Row] = [Row()]
    @State private var transmitterIndex = 0
    @State private var mode = "FM"
    @State private var defaultTime = Date()
    @State private var errorMessage: String?
    @FocusState private var focusedRow: UUID?

    /// Transmitters worth logging against: anything with a downlink.
    private var candidateTransmitters: [SatNOGSTransmitter] {
        transmitters.filter { $0.downlinkLow != nil }
    }

    private var selectedTransmitter: SatNOGSTransmitter? {
        guard candidateTransmitters.indices.contains(transmitterIndex) else {
            return candidateTransmitters.first
        }
        return candidateTransmitters[transmitterIndex]
    }

    /// ADIF FREQ/BAND are your TX side = the uplink. Beacon-only transmitters
    /// (no uplink) fall back to the downlink so the QSO still gets a band.
    private var sessionFrequencyMHz: Double? {
        guard let transmitter = selectedTransmitter else {
            return nil
        }
        let hertz = transmitter.uplinkLow ?? transmitter.downlinkLow
        return hertz.map { Double($0) / 1_000_000 }
    }

    private var filledRowCount: Int {
        rows.count(where: { !$0.callsign.trimmingCharacters(in: .whitespaces).isEmpty })
    }

    private var saveTitle: String {
        filledRowCount > 1 ? "Log \(filledRowCount)" : "Log"
    }

    private var headerSection: some View {
        Section {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(satName)
                        .font(.headline.monospaced())
                    if let detailName {
                        Text(detailName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text("SAT")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .clipShape(Capsule())
            }
            if let pass {
                HStack {
                    Text("Pass")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(
                        "\(pass.aos.formatted(date: .omitted, time: .shortened)) – "
                            + "\(pass.los.formatted(date: .omitted, time: .shortened)) · "
                            + String(format: "%.0f° max", pass.peakElevationDeg)
                    )
                    .font(.caption.monospacedDigit())
                }
            }
        } footer: {
            Text("Logged with SAT_NAME \(satName) and PROP_MODE SAT for LoTW satellite credit.")
        }
    }

    private var tuningSection: some View {
        Section("Transmitter") {
            if !candidateTransmitters.isEmpty {
                Picker("Transmitter", selection: $transmitterIndex) {
                    ForEach(Array(candidateTransmitters.enumerated()), id: \.offset) { index, transmitter in
                        Text(transmitterLabel(transmitter))
                            .tag(index)
                    }
                }
                .onChange(of: transmitterIndex) {
                    if let txMode = selectedTransmitter?.mode, !txMode.isEmpty {
                        mode = normalizedMode(txMode)
                    }
                }
            }
            Picker("Mode", selection: $mode) {
                ForEach(["FM", "SSB", "CW", "DATA"], id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.segmented)
            DatePicker(
                "QSO time",
                selection: $defaultTime,
                displayedComponents: [.hourAndMinute]
            )
        }
    }

    private var contactsSection: some View {
        Section("Contacts") {
            ForEach($rows) { $row in
                contactRow($row)
            }
        }
    }

    private func contactRow(_ row: Binding<Row>) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                TextField("Callsign", text: row.callsign)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .font(.body.monospaced())
                    .focused($focusedRow, equals: row.id)
                    .onSubmit { advanceFocus(from: row.id) }
                    .onChange(of: row.wrappedValue.callsign) {
                        appendEmptyRowIfNeeded()
                    }
                TextField("Grid", text: row.grid)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                    .frame(width: 90)
                Button {
                    row.wrappedValue.showTime.toggle()
                    if row.wrappedValue.time == nil {
                        row.wrappedValue.time = defaultTime
                    }
                } label: {
                    Image(systemName: "clock")
                        .foregroundStyle(row.wrappedValue.showTime ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Set per-contact time")
            }
            if row.wrappedValue.showTime {
                DatePicker(
                    "Time",
                    selection: Binding(
                        get: { row.wrappedValue.time ?? defaultTime },
                        set: { row.wrappedValue.time = $0 }
                    ),
                    displayedComponents: [.hourAndMinute]
                )
                .font(.caption)
            }
        }
    }

    private func transmitterLabel(_ transmitter: SatNOGSTransmitter) -> String {
        var parts: [String] = []
        if let mode = transmitter.mode, !mode.isEmpty {
            parts.append(mode)
        }
        if let downlink = transmitter.downlinkLow {
            parts.append(String(format: "↓ %.3f", Double(downlink) / 1_000_000))
        }
        if let uplink = transmitter.uplinkLow {
            parts.append(String(format: "↑ %.3f", Double(uplink) / 1_000_000))
        }
        return parts.isEmpty ? transmitter.description : parts.joined(separator: " ")
    }

    /// Collapse SatNOGS mode strings onto the logger's mode set.
    private func normalizedMode(_ raw: String) -> String {
        let upper = raw.uppercased()
        if upper.contains("FM") {
            return "FM"
        }
        if upper.contains("CW") {
            return "CW"
        }
        if upper.contains("SSB") || upper.contains("USB") || upper.contains("LSB")
            || upper.contains("LINEAR") || upper.contains("TRANSPONDER")
        {
            return "SSB"
        }
        return "DATA"
    }

    private func prefill() {
        if let pass {
            defaultTime = pass.peak
        }
        // One row per recording mark, back-dated to the tap; the operator
        // fills callsign + grid while scrubbing the audio around each mark.
        if let recording, !recording.markOffsets.isEmpty {
            var seeded = recording.markDates.map { markDate -> Row in
                var row = Row()
                row.time = markDate
                return row
            }
            seeded.append(Row())
            rows = seeded
        }
        // Preselect the same primary the pointing view tunes: active with
        // both links, else the first downlink-bearing transmitter.
        if let index = candidateTransmitters.firstIndex(where: {
            $0.isActive && $0.uplinkLow != nil && $0.downlinkLow != nil
        }) {
            transmitterIndex = index
        }
        if let txMode = selectedTransmitter?.mode, !txMode.isEmpty {
            mode = normalizedMode(txMode)
        }
        focusedRow = rows.first?.id
    }

    private func advanceFocus(from id: UUID) {
        appendEmptyRowIfNeeded()
        guard let index = rows.firstIndex(where: { $0.id == id }) else {
            return
        }
        let next = rows.index(after: index)
        if rows.indices.contains(next) {
            focusedRow = rows[next].id
        }
    }

    private func appendEmptyRowIfNeeded() {
        let hasEmpty = rows.contains {
            $0.callsign.trimmingCharacters(in: .whitespaces).isEmpty
        }
        if !hasEmpty {
            rows.append(Row())
        }
    }

    private func save() {
        let contacts = rows.compactMap { row -> SatelliteQuickLogService.Contact? in
            let callsign = row.callsign.trimmingCharacters(in: .whitespaces).uppercased()
            guard !callsign.isEmpty else {
                return nil
            }
            let grid = row.grid.trimmingCharacters(in: .whitespaces).uppercased()
            return SatelliteQuickLogService.Contact(
                callsign: callsign,
                grid: grid.isEmpty ? nil : grid,
                timestamp: row.time ?? defaultTime
            )
        }
        let times = contacts.map(\.timestamp)
        let context = SatelliteQuickLogService.PassContext(
            satName: satName,
            mode: mode,
            uplinkMHz: sessionFrequencyMHz,
            passStart: pass?.aos ?? times.min() ?? Date(),
            passEnd: pass?.los ?? times.max() ?? Date(),
            myGrid: observerGrid
        )
        do {
            let count = try SatelliteQuickLogService.log(
                contacts: contacts, pass: context, modelContext: modelContext
            )
            ToastManager.shared.show(
                .success,
                message: "Logged \(count) QSO\(count == 1 ? "" : "s") on \(satName)"
            )
            onLogged(count)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - ScanRowEditSheet

/// Edit sheet for a single scanned row. Two editing modes:
/// - **Quick Entry**: type a line and let the parser handle it (same as the logger)
/// - **Fields**: edit each field individually
struct ScanRowEditSheet: View {
    // MARK: Lifecycle

    init(
        row: ScannedQSORow,
        rstOrder: RSTOrder,
        onSave: @escaping (ScannedQSORow) -> Void
    ) {
        originalRow = row
        self.rstOrder = rstOrder
        self.onSave = onSave
        _quickEntryText = State(initialValue: row.rawText)
        _callsign = State(initialValue: row.parseResult?.callsign ?? "")
        _frequency = State(initialValue: Self.frequencyString(row.parseResult?.frequency))
        _mode = State(initialValue: row.parseResult?.mode ?? "")
        _rstSent = State(initialValue: row.parseResult?.rstSent ?? "")
        _rstReceived = State(initialValue: row.parseResult?.rstReceived ?? "")
        _notes = State(initialValue: row.parseResult?.notes ?? "")
        _state = State(initialValue: row.parseResult?.state ?? "")
        _theirPark = State(initialValue: row.parseResult?.theirPark ?? "")
        _timestamp = State(initialValue: row.timestamp ?? Date())
        _hasTimestamp = State(initialValue: row.timestamp != nil)
    }

    // MARK: Internal

    var body: some View {
        NavigationStack {
            Form {
                rowImageSection
                editModePicker
                if useQuickEntry {
                    quickEntrySection
                } else {
                    fieldsSection
                }
                timestampSection
            }
            .navigationTitle("Edit Row")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: quickEntryText) {
                if let zt = quickEntryParseResult?.zuluTime {
                    timestamp = zt.dateToday()
                    hasTimestamp = true
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(saveDisabled)
                }
            }
        }
    }

    // MARK: Private

    private static let utcTimeZone = TimeZone(identifier: "UTC")!

    @Environment(\.dismiss) private var dismiss

    @State private var useQuickEntry = true
    @State private var quickEntryText: String

    // Field-editing state
    @State private var callsign: String
    @State private var frequency: String
    @State private var mode: String
    @State private var rstSent: String
    @State private var rstReceived: String
    @State private var notes: String
    @State private var state: String
    @State private var theirPark: String
    @State private var timestamp: Date
    @State private var hasTimestamp: Bool

    private let originalRow: ScannedQSORow
    private let rstOrder: RSTOrder
    private let onSave: (ScannedQSORow) -> Void

    private var saveDisabled: Bool {
        if useQuickEntry {
            return quickEntryParseResult == nil
        }
        return callsign.isEmpty
    }

    private var quickEntryParseResult: QuickEntryResult? {
        QuickEntryParser.parse(quickEntryText, rstOrder: rstOrder)
    }

    private var quickEntryTokens: [ParsedToken] {
        QuickEntryParser.parseTokens(quickEntryText, rstOrder: rstOrder)
    }
}

// MARK: - Sections

private extension ScanRowEditSheet {
    @ViewBuilder
    var rowImageSection: some View {
        if let image = originalRow.rowImage {
            Section {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } header: {
                Text("Scanned Image")
            }
        }
    }

    var editModePicker: some View {
        Picker("Edit Mode", selection: $useQuickEntry) {
            Text("Quick Entry").tag(true)
            Text("Fields").tag(false)
        }
        .pickerStyle(.segmented)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
    }

    var quickEntrySection: some View {
        Section {
            TextField("e.g. W1AW 14.250 SSB 59 59", text: $quickEntryText)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.body.monospaced())

            if !quickEntryTokens.isEmpty {
                tokenPreview
            } else if !quickEntryText.isEmpty {
                Text("Could not parse — needs a valid callsign")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Quick Entry")
        } footer: {
            Text("Type as you would in the logger: callsign, frequency, mode, RSTs, state, park.")
        }
    }

    var tokenPreview: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(quickEntryTokens) { token in
                    VStack(spacing: 2) {
                        Text(token.text)
                            .font(.caption.monospaced())
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(token.type.color.opacity(0.2))
                            .foregroundStyle(token.type.color)
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                        Text(token.type.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    var fieldsSection: some View {
        Group {
            Section {
                TextField("Callsign", text: $callsign)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())

                TextField("Frequency (MHz)", text: $frequency)
                    .keyboardType(.decimalPad)

                TextField("Mode", text: $mode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            } header: {
                Text("Contact")
            }

            Section {
                TextField("RST Sent", text: $rstSent)
                    .keyboardType(.numberPad)
                TextField("RST Received", text: $rstReceived)
                    .keyboardType(.numberPad)
            } header: {
                Text("Signal Reports")
            }

            Section {
                TextField("State / Region", text: $state)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                TextField("Their Park (e.g. US-0001)", text: $theirPark)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                TextField("Notes", text: $notes)
            } header: {
                Text("Details")
            }
        }
    }

    var timestampSection: some View {
        Section {
            Toggle("Has Timestamp", isOn: $hasTimestamp)
            if hasTimestamp {
                DatePicker(
                    "Date & Time (UTC)",
                    selection: $timestamp,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .environment(\.timeZone, Self.utcTimeZone)
            }
        } header: {
            Text("Timestamp (UTC)")
        }
    }
}

// MARK: - Save

private extension ScanRowEditSheet {
    func save() {
        var result: QuickEntryResult
        if useQuickEntry, let parsed = quickEntryParseResult {
            result = parsed
        } else {
            let freq = Double(frequency)
            let band = freq.flatMap { BandUtilities.deriveBand(from: $0 * 1_000) }
            result = QuickEntryResult(
                callsign: callsign.uppercased(),
                rstSent: rstSent.isEmpty ? nil : rstSent,
                rstReceived: rstReceived.isEmpty ? nil : rstReceived,
                state: state.isEmpty ? nil : state.uppercased(),
                theirPark: theirPark.isEmpty ? nil : theirPark.uppercased(),
                frequency: freq,
                band: band,
                mode: mode.isEmpty ? nil : mode.uppercased(),
                notes: notes.isEmpty ? nil : notes
            )
        }

        var updated = originalRow
        updated.parseResult = result

        // If quick entry parsed a Zulu time, apply it to the timestamp
        if let zt = result.zuluTime {
            updated.timestamp = zt.dateToday()
        } else {
            updated.timestamp = hasTimestamp ? timestamp : nil
        }

        onSave(updated)
        dismiss()
    }

    static func frequencyString(_ freq: Double?) -> String {
        guard let freq, freq > 0 else {
            return ""
        }
        return String(format: "%.3f", freq)
    }
}

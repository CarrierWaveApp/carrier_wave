import CarrierWaveCore
import SwiftData
import SwiftUI

// MARK: - QSOEditSheet

/// Sheet for editing QSO fields from the Logs tab detail view.
struct QSOEditSheet: View {
    // MARK: Lifecycle

    init(qso: QSO, onSave: @escaping () -> Void) {
        self.qso = qso
        self.onSave = onSave

        _callsign = State(initialValue: qso.callsign)
        _originalCallsign = State(initialValue: qso.callsign)
        _band = State(initialValue: qso.band)
        _mode = State(initialValue: qso.mode)
        _frequencyText = State(
            initialValue: qso.frequency.map { FrequencyFormatter.format($0) } ?? ""
        )
        _timestamp = State(initialValue: qso.timestamp)
        _rstSent = State(initialValue: qso.rstSent ?? "")
        _rstReceived = State(initialValue: qso.rstReceived ?? "")
        _name = State(initialValue: qso.name ?? "")
        _myGrid = State(initialValue: qso.myGrid ?? "")
        _theirGrid = State(initialValue: qso.theirGrid ?? "")
        _parkReference = State(initialValue: qso.parkReference ?? "")
        _theirParkReference = State(initialValue: qso.theirParkReference ?? "")
        _sotaRef = State(initialValue: qso.sotaRef ?? "")
        _powerText = State(initialValue: qso.power.map { String($0) } ?? "")
        _notes = State(initialValue: qso.notes ?? "")
        _qth = State(initialValue: qso.qth ?? "")
        _state = State(initialValue: qso.state ?? "")
        _country = State(initialValue: qso.country ?? "")
    }

    // MARK: Internal

    var body: some View {
        NavigationStack {
            Form {
                contactSection
                signalSection
                locationSection
                notesSection
            }
            .navigationTitle("Edit QSO")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                }
            }
        }
    }

    // MARK: Private

    private static let bands = [
        "160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m",
        "6m", "2m", "70cm",
    ]

    private static let modes = [
        "SSB", "CW", "FT8", "FT4", "RTTY", "AM", "FM", "DIGI",
    ]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var callsign: String
    @State private var originalCallsign: String
    @State private var band: String
    @State private var mode: String
    @State private var frequencyText: String
    @State private var timestamp: Date
    @State private var rstSent: String
    @State private var rstReceived: String
    @State private var name: String
    @State private var myGrid: String
    @State private var theirGrid: String
    @State private var parkReference: String
    @State private var theirParkReference: String
    @State private var sotaRef: String
    @State private var powerText: String
    @State private var notes: String
    @State private var qth: String
    @State private var state: String
    @State private var country: String

    private let qso: QSO
    private let onSave: () -> Void

    private var isValid: Bool {
        !callsign.trimmingCharacters(in: .whitespaces).isEmpty
            && !band.isEmpty
            && !mode.isEmpty
    }

    // MARK: - Sections

    private var contactSection: some View {
        Section("Contact") {
            TextField("Callsign", text: $callsign)
                .font(.body.monospaced())
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()

            Picker("Band", selection: $band) {
                ForEach(Self.bandOptions(current: band), id: \.self) { bandOption in
                    Text(bandOption).tag(bandOption)
                }
            }

            Picker("Mode", selection: $mode) {
                ForEach(Self.modeOptions(current: mode), id: \.self) { modeOption in
                    Text(modeOption).tag(modeOption)
                }
            }

            HStack {
                Text("Frequency")
                Spacer()
                TextField("MHz", text: $frequencyText)
                    .font(.body.monospaced())
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
            }

            DatePicker(
                "Date/Time (UTC)",
                selection: $timestamp,
                displayedComponents: [.date, .hourAndMinute]
            )
            .environment(\.timeZone, TimeZone(identifier: "UTC")!)

            TextField("Name", text: $name)
                .textInputAutocapitalization(.words)
        }
    }

    private var signalSection: some View {
        Section("Signal") {
            HStack {
                Text("RST Sent")
                Spacer()
                TextField("599", text: $rstSent)
                    .font(.body.monospaced())
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 80)
            }

            HStack {
                Text("RST Received")
                Spacer()
                TextField("599", text: $rstReceived)
                    .font(.body.monospaced())
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 80)
            }

            HStack {
                Text("Power")
                Spacer()
                TextField("W", text: $powerText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 80)
                Text("W")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var locationSection: some View {
        Section("Location") {
            HStack {
                Text("My Grid")
                Spacer()
                TextField("FN31", text: $myGrid)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
            }

            HStack {
                Text("Their Grid")
                Spacer()
                TextField("FN31", text: $theirGrid)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
            }

            HStack {
                Text("My Park")
                Spacer()
                TextField("K-1234", text: $parkReference)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
            }

            HStack {
                Text("Their Park")
                Spacer()
                TextField("K-1234", text: $theirParkReference)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
            }

            HStack {
                Text("SOTA Ref")
                Spacer()
                TextField("W7W/KG-049", text: $sotaRef)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 140)
            }

            TextField("QTH", text: $qth)
            TextField("State", text: $state)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            TextField("Country", text: $country)
                .textInputAutocapitalization(.words)
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextField("Notes", text: $notes, axis: .vertical)
                .lineLimit(3 ... 8)
        }
    }

    // MARK: - Helpers

    /// Build band options, ensuring the current value is included even if non-standard
    private static func bandOptions(current: String) -> [String] {
        if bands.contains(current) {
            return bands
        }
        return [current] + bands
    }

    /// Build mode options, ensuring the current value is included even if non-standard
    private static func modeOptions(current: String) -> [String] {
        if modes.contains(current) {
            return modes
        }
        return [current] + modes
    }

    private func save() {
        let trimmedCallsign = callsign.trimmingCharacters(in: .whitespaces).uppercased()
        guard !trimmedCallsign.isEmpty else {
            return
        }

        let callsignChanged = trimmedCallsign != originalCallsign

        qso.callsign = trimmedCallsign
        qso.band = band
        qso.mode = mode
        qso.frequency = FrequencyFormatter.parse(frequencyText)
        qso.timestamp = timestamp
        qso.rstSent = rstSent.nonEmpty
        qso.rstReceived = rstReceived.nonEmpty
        qso.name = name.nonEmpty
        qso.myGrid = myGrid.trimmingCharacters(in: .whitespaces).uppercased().nonEmpty
        qso.theirGrid = theirGrid.trimmingCharacters(in: .whitespaces).uppercased().nonEmpty
        qso.parkReference = parkReference.trimmingCharacters(in: .whitespaces)
            .uppercased().nonEmpty
        qso.theirParkReference = theirParkReference.trimmingCharacters(in: .whitespaces)
            .uppercased().nonEmpty
        qso.sotaRef = sotaRef.trimmingCharacters(in: .whitespaces).uppercased().nonEmpty
        qso.power = Int(powerText)
        qso.notes = notes.trimmingCharacters(in: .whitespaces).nonEmpty
        qso.qth = qth.trimmingCharacters(in: .whitespaces).nonEmpty
        qso.state = state.trimmingCharacters(in: .whitespaces).uppercased().nonEmpty
        qso.country = country.trimmingCharacters(in: .whitespaces).nonEmpty
        qso.cloudDirtyFlag = true

        try? modelContext.save()

        if callsignChanged {
            let context = modelContext
            Task {
                let service = CallsignLookupService(modelContext: context)
                guard let info = await service.lookup(trimmedCallsign) else {
                    return
                }
                qso.name = info.name
                qso.theirGrid = info.grid
                qso.state = info.state
                qso.country = info.country
                qso.qth = info.qth
                qso.theirLicenseClass = info.licenseClass
                try? context.save()
            }
        }

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onSave()
        dismiss()
    }
}

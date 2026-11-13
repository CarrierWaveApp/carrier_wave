import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - LoggerQSOEditSheet

/// Sheet for editing an existing QSO from the logger tab
struct LoggerQSOEditSheet: View {
    // MARK: Internal

    let qso: QSO
    /// Callback when QSO is deleted (hidden)
    var onDelete: (() -> Void)?

    var body: some View {
        NavigationStack {
            Form {
                if let changeNote = qso.callsignChangeNote {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundStyle(.orange)
                                .font(.caption)
                            Text(changeNote)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Section("Contact") {
                    HStack {
                        Text("Callsign")
                        Spacer()
                        TextField("Callsign", text: $callsign)
                            .font(.body.monospaced())
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    }

                    HStack {
                        Text("Frequency")
                        Spacer()
                        TextField("MHz", text: $frequencyText)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            .font(.body.monospaced())
                            .frame(width: 120)
                            .onChange(of: frequencyText) { _, newValue in
                                guard
                                    let parsed = FrequencyFormatter.parse(newValue),
                                    let derived = BandUtilities.deriveBand(from: parsed * 1_000)
                                else {
                                    return
                                }
                                band = derived
                            }
                    }

                    HStack {
                        Text("Band")
                        Spacer()
                        Text(band.isEmpty ? "—" : band)
                            .foregroundStyle(band.isEmpty ? .tertiary : .secondary)
                            .font(.body.monospaced())
                    }

                    DatePicker(
                        "Time",
                        selection: $timestamp,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                Section("Signal Reports") {
                    HStack {
                        Text("Sent")
                        Spacer()
                        TextField("599", text: $rstSent)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                            .frame(width: 60)
                    }

                    HStack {
                        Text("Received")
                        Spacer()
                        TextField("599", text: $rstReceived)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                            .frame(width: 60)
                    }
                }

                Section("Station Info") {
                    HStack {
                        Text("Name")
                        Spacer()
                        TextField("Name", text: $name)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Text("State")
                        Spacer()
                        TextField("ST", text: $state)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .frame(width: 60)
                    }

                    HStack {
                        Text("Grid")
                        Spacer()
                        TextField("Grid", text: $grid)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.characters)
                            .frame(width: 80)
                    }

                    HStack {
                        Text("Their Park")
                        Spacer()
                        TextField("K-1234", text: $theirPark)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.characters)
                            .frame(width: 100)
                    }

                    // Their Summit (S2S) — editable. Hidden when there's no
                    // SOTA context on the session and no existing value.
                    if isSOTASession || !theirSummit.isEmpty {
                        HStack {
                            Text("Their Summit")
                            Spacer()
                            TextField("W6/CT-225", text: $theirSummit)
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .frame(width: 120)
                        }
                    }

                    // My Summit (read-only, from session). Lets the user
                    // tell at a glance which QSOs got an S2S tag — they
                    // share `My Summit`, only some have `Their Summit`.
                    if !mySummit.isEmpty {
                        HStack {
                            Text("My Summit")
                            Spacer()
                            Text(mySummit)
                                .font(.body.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if qso.aoaCode != nil || isAoASession {
                    Section("AoA") {
                        HStack {
                            Text("Code Exchange")
                            Spacer()
                            TextField("Exchanged code", text: $aoaCode)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 120)
                        }
                    }
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3 ... 6)
                }

                if qso.stationProfileName != nil || qso.myGrid != nil {
                    Section("My Station") {
                        if let profileName = qso.stationProfileName {
                            HStack {
                                Text("Station")
                                Spacer()
                                Text(profileName)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if let myGrid = qso.myGrid {
                            HStack {
                                Text("Grid")
                                Spacer()
                                Text(myGrid)
                                    .font(.body.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Delete QSO")
                            Spacer()
                        }
                    }
                    .confirmationDialog(
                        "Delete QSO?",
                        isPresented: $showDeleteConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Delete", role: .destructive) {
                            hideQSO()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text(
                            "This QSO will be hidden and won't sync to any services."
                        )
                    }
                }
            }
            .navigationTitle("Edit QSO")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadQSOData()
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var callsign = ""
    @State private var originalCallsign = ""
    @State private var frequencyText = ""
    @State private var band = ""
    @State private var timestamp = Date()
    @State private var rstSent = ""
    @State private var rstReceived = ""
    @State private var name = ""
    @State private var state = ""
    @State private var grid = ""
    @State private var theirPark = ""
    @State private var theirSummit = ""
    @State private var mySummit = ""
    @State private var isSOTASession = false
    @State private var notes = ""
    @State private var aoaCode = ""
    @State private var showDeleteConfirmation = false
    @State private var isAoASession = false

    private func saveChanges() {
        let newCallsign = callsign.trimmingCharacters(in: .whitespaces).uppercased()
        let callsignChanged = newCallsign != originalCallsign

        // Preserve the very-first contact callsign so download-merge can match
        // against the pre-edit value. See CAR-245.
        if callsignChanged, qso.originalCallsign == nil,
           !originalCallsign.trimmingCharacters(in: .whitespaces).isEmpty
        {
            qso.originalCallsign = originalCallsign
        }

        qso.callsign = newCallsign
        qso.frequency = FrequencyFormatter.parse(frequencyText)
        if !band.isEmpty {
            qso.band = band
        }
        qso.timestamp = timestamp
        qso.rstSent = rstSent.isEmpty ? nil : rstSent
        qso.rstReceived = rstReceived.isEmpty ? nil : rstReceived
        qso.name = name.isEmpty ? nil : name
        qso.state = state.trimmingCharacters(in: .whitespaces).uppercased().isEmpty
            ? nil : state.trimmingCharacters(in: .whitespaces).uppercased()
        qso.theirGrid = grid.isEmpty ? nil : grid
        qso.theirParkReference = theirPark.isEmpty ? nil : theirPark
        qso.sotaRef = theirSummit
            .trimmingCharacters(in: .whitespaces)
            .uppercased()
            .nonEmpty
        qso.notes = notes.isEmpty ? nil : notes
        // User edited notes in the LoggerView edit sheet — tag as user-authored. CAR-243.
        if !notes.isEmpty {
            qso.notesUserAuthored = true
        }
        qso.aoaCode = aoaCode.isEmpty ? nil : aoaCode
        qso.cloudDirtyFlag = true
        qso.modifiedAt = Date()
        try? modelContext.save()

        if callsignChanged {
            let context = modelContext
            Task {
                let service = CallsignLookupService(modelContext: context)
                guard let info = await service.lookup(newCallsign) else {
                    return
                }
                qso.name = info.name
                qso.theirGrid = info.grid
                qso.state = info.state
                qso.country = info.country
                qso.qth = info.qth
                qso.theirLicenseClass = info.licenseClass
                qso.callsignChangeNote = info.callsignChangeNote
                try? context.save()
            }
        }
    }

    private func hideQSO() {
        dismiss()
        onDelete?()
    }
}

// MARK: - LoggerQSOEditSheet Loading

extension LoggerQSOEditSheet {
    /// Populate form fields from the QSO + its parent session. Split out
    /// so the main struct stays under SwiftLint's type-body cap.
    func loadQSOData() {
        callsign = qso.callsign
        originalCallsign = qso.callsign
        frequencyText = qso.frequency.map { FrequencyFormatter.format($0) } ?? ""
        band = qso.band
        timestamp = qso.timestamp
        rstSent = qso.rstSent ?? "599"
        rstReceived = qso.rstReceived ?? "599"
        name = qso.name ?? ""
        state = qso.state ?? ""
        grid = qso.theirGrid ?? ""
        theirPark = qso.theirParkReference ?? ""
        theirSummit = qso.sotaRef ?? ""
        notes = qso.notes ?? ""
        aoaCode = qso.aoaCode ?? ""

        // Load session-derived context once: AoA flag (controls AoA
        // section visibility), `mySummit` (read-only, from
        // session.sotaReference), and `isSOTASession` (governs whether
        // the Their Summit row is shown for QSOs that don't already
        // carry a value).
        if let sessionId = qso.loggingSessionId {
            let predicate = #Predicate<LoggingSession> { $0.id == sessionId }
            let descriptor = FetchDescriptor<LoggingSession>(predicate: predicate)
            let session = (try? modelContext.fetch(descriptor))?.first
            isAoASession = session?.activationType == .aoa
            isSOTASession = session?.isSOTA ?? false
            mySummit = session?.sotaReference ?? ""
        }
    }
}

// MARK: - SessionTitleEditSheet

/// Sheet for editing the session title
struct SessionTitleEditSheet: View {
    // MARK: Internal

    @Binding var title: String

    let defaultTitle: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextField("Session title", text: $title)
                    .font(.title3)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)

                Text("Leave empty to use default: \(defaultTitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding()
            .navigationTitle("Edit Title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(title)
                    }
                }
            }
            .onAppear {
                isFocused = true
            }
        }
    }

    // MARK: Private

    @FocusState private var isFocused: Bool
}

// MARK: - SessionParkEditSheet

/// Sheet for editing parks on an active POTA session (supports n-fer)
struct SessionParkEditSheet: View {
    @Binding var parkReference: String

    let userGrid: String?
    let onSave: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ParkEntryField(
                        parkReference: $parkReference,
                        label: "Parks",
                        placeholder: "K-1234",
                        userGrid: userGrid,
                        defaultCountry: "US"
                    )
                } footer: {
                    Text("Add or remove parks for this n-fer activation")
                }
            }
            .navigationTitle("Edit Parks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(parkReference)
                    }
                    .disabled(parkReference.isEmpty)
                }
            }
        }
    }
}

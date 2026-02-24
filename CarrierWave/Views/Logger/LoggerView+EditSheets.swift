import CarrierWaveCore
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
    @State private var timestamp = Date()
    @State private var rstSent = ""
    @State private var rstReceived = ""
    @State private var name = ""
    @State private var state = ""
    @State private var grid = ""
    @State private var theirPark = ""
    @State private var notes = ""
    @State private var showDeleteConfirmation = false

    private func loadQSOData() {
        callsign = qso.callsign
        originalCallsign = qso.callsign
        timestamp = qso.timestamp
        rstSent = qso.rstSent ?? "599"
        rstReceived = qso.rstReceived ?? "599"
        name = qso.name ?? ""
        state = qso.state ?? ""
        grid = qso.theirGrid ?? ""
        theirPark = qso.theirParkReference ?? ""
        notes = qso.notes ?? ""
    }

    private func saveChanges() {
        let newCallsign = callsign.trimmingCharacters(in: .whitespaces).uppercased()
        let callsignChanged = newCallsign != originalCallsign

        qso.callsign = newCallsign
        qso.timestamp = timestamp
        qso.rstSent = rstSent.isEmpty ? nil : rstSent
        qso.rstReceived = rstReceived.isEmpty ? nil : rstReceived
        qso.name = name.isEmpty ? nil : name
        qso.state = state.trimmingCharacters(in: .whitespaces).uppercased().isEmpty
            ? nil : state.trimmingCharacters(in: .whitespaces).uppercased()
        qso.theirGrid = grid.isEmpty ? nil : grid
        qso.theirParkReference = theirPark.isEmpty ? nil : theirPark
        qso.notes = notes.isEmpty ? nil : notes
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
                try? context.save()
            }
        }
    }

    private func hideQSO() {
        dismiss()
        onDelete?()
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

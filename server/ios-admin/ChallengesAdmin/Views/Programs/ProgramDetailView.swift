import SwiftUI

// MARK: - ProgramDetailView

struct ProgramDetailView: View {
    // MARK: Lifecycle

    init(program: ProgramResponse, onSaved: @escaping () async -> Void) {
        _program = State(initialValue: program)
        self.onSaved = onSaved
    }

    // MARK: Internal

    @EnvironmentObject var config: ServerConfig

    let onSaved: () async -> Void

    var body: some View {
        List {
            Section("Identity") {
                LabeledContent("Slug") {
                    Text(program.slug).fontDesign(.monospaced)
                }
                LabeledContent("Name") {
                    Text(program.name)
                }
                LabeledContent("Short Name") {
                    Text(program.shortName)
                }
                LabeledContent("Icon") {
                    Text(program.icon)
                }
                LabeledContent("Status") {
                    Text(program.isActive ? "Active" : "Inactive")
                        .foregroundStyle(program.isActive ? .green : .secondary)
                }
            }

            Section("References") {
                LabeledContent("Label") {
                    Text(program.referenceLabel)
                }
                if let format = program.referenceFormat {
                    LabeledContent("Format") {
                        Text(format).fontDesign(.monospaced)
                    }
                }
                if let example = program.referenceExample {
                    LabeledContent("Example") {
                        Text(example).fontDesign(.monospaced).foregroundStyle(.blue)
                    }
                }
            }

            Section("Features") {
                LabeledContent("Multi-Ref") {
                    Text(program.multiRefAllowed ? "Yes" : "No")
                }
                LabeledContent("Supports Rove") {
                    Text(program.supportsRove ? "Yes" : "No")
                }
                if let threshold = program.activationThreshold {
                    LabeledContent("Activation Threshold") {
                        Text("\(threshold)").fontDesign(.monospaced)
                    }
                }
            }

            if !program.capabilities.isEmpty {
                Section("Capabilities") {
                    ForEach(program.capabilities, id: \.self) { cap in
                        Text(cap).font(.subheadline).fontDesign(.monospaced)
                    }
                }
            }

            if let website = program.website, !website.isEmpty {
                Section("Links") {
                    LabeledContent("Website") {
                        Text(website)
                            .foregroundStyle(.blue)
                            .lineLimit(1)
                    }
                }
            }
        }
        .navigationTitle(program.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingEditSheet = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            EditProgramSheet(program: program) { updated in
                program = updated
                Task { await onSaved() }
            }
        }
    }

    // MARK: Private

    @State private var program: ProgramResponse

    @State private var showingEditSheet = false
}

// MARK: - EditProgramSheet

struct EditProgramSheet: View {
    // MARK: Lifecycle

    init(program: ProgramResponse, onSaved: @escaping (ProgramResponse) -> Void) {
        self.program = program
        self.onSaved = onSaved
        _name = State(initialValue: program.name)
        _shortName = State(initialValue: program.shortName)
        _icon = State(initialValue: program.icon)
        _website = State(initialValue: program.website ?? "")
        _referenceLabel = State(initialValue: program.referenceLabel)
        _referenceFormat = State(initialValue: program.referenceFormat ?? "")
        _referenceExample = State(initialValue: program.referenceExample ?? "")
        _multiRefAllowed = State(initialValue: program.multiRefAllowed)
        _supportsRove = State(initialValue: program.supportsRove)
        _isActive = State(initialValue: program.isActive)
        _sortOrder = State(initialValue: "0")
    }

    // MARK: Internal

    @EnvironmentObject var config: ServerConfig

    let program: ProgramResponse
    let onSaved: (ProgramResponse) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    LabeledContent("Slug") {
                        Text(program.slug).fontDesign(.monospaced).foregroundStyle(.secondary)
                    }
                    TextField("Name", text: $name)
                    TextField("Short Name", text: $shortName)
                    TextField("Icon (emoji)", text: $icon)
                }

                Section("References") {
                    TextField("Reference Label", text: $referenceLabel)
                    TextField("Reference Format", text: $referenceFormat)
                        .fontDesign(.monospaced)
                    TextField("Reference Example", text: $referenceExample)
                        .fontDesign(.monospaced)
                }

                Section("Links") {
                    TextField("Website URL", text: $website)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                }

                Section {
                    Toggle("Active", isOn: $isActive)
                    Toggle("Multi-Ref Allowed", isOn: $multiRefAllowed)
                    Toggle("Supports Rove", isOn: $supportsRove)
                }

                if let error {
                    Section {
                        Text(error).foregroundStyle(.red).font(.subheadline)
                    }
                }
            }
            .navigationTitle("Edit Program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(name.isEmpty || shortName.isEmpty || icon.isEmpty || referenceLabel
                        .isEmpty || isSubmitting)
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var shortName: String
    @State private var icon: String
    @State private var website: String
    @State private var referenceLabel: String
    @State private var referenceFormat: String
    @State private var referenceExample: String
    @State private var multiRefAllowed: Bool
    @State private var supportsRove: Bool
    @State private var isActive: Bool
    @State private var sortOrder: String
    @State private var isSubmitting = false
    @State private var error: String?

    private func save() async {
        isSubmitting = true
        error = nil
        let api = APIClient(config: config)
        let request = UpdateProgramRequest(
            name: name,
            shortName: shortName,
            icon: icon,
            website: website.isEmpty ? nil : website,
            referenceLabel: referenceLabel,
            referenceFormat: referenceFormat.isEmpty ? nil : referenceFormat,
            referenceExample: referenceExample.isEmpty ? nil : referenceExample,
            multiRefAllowed: multiRefAllowed,
            supportsRove: supportsRove,
            isActive: isActive
        )
        do {
            let updated = try await api.updateProgram(slug: program.slug, request)
            onSaved(updated)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isSubmitting = false
    }
}

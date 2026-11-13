import SwiftUI

// MARK: - ProgramsListView

struct ProgramsListView: View {
    // MARK: Internal

    @EnvironmentObject var config: ServerConfig

    var body: some View {
        NavigationStack {
            List {
                if let error {
                    ErrorBanner(message: error)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }

                ForEach(programs) { program in
                    NavigationLink(destination: ProgramDetailView(
                        program: program,
                        onSaved: { await loadPrograms() }
                    )) {
                        ProgramRow(program: program)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            programToDelete = program
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Programs (\(programs.count))")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .refreshable { await loadPrograms() }
            .task { await loadPrograms() }
            .overlay {
                if isLoading, programs.isEmpty {
                    ProgressView()
                } else if programs.isEmpty, error == nil {
                    ContentUnavailableView(
                        "No Programs",
                        systemImage: "list.bullet",
                        description: Text("Create a program to get started.")
                    )
                }
            }
            .sheet(isPresented: $showingCreateSheet) {
                CreateProgramSheet { await loadPrograms() }
            }
            .alert("Delete Program?", isPresented: .init(
                get: { programToDelete != nil },
                set: {
                    if !$0 {
                        programToDelete = nil
                    }
                }
            )) {
                Button("Cancel", role: .cancel) { programToDelete = nil }
                Button("Delete", role: .destructive) {
                    if let program = programToDelete {
                        Task { await deleteProgram(program) }
                    }
                }
            } message: {
                if let program = programToDelete {
                    Text("This will permanently delete the \"\(program.name)\" program.")
                }
            }
        }
    }

    // MARK: Private

    @State private var programs: [ProgramResponse] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var showingCreateSheet = false
    @State private var programToDelete: ProgramResponse?

    private var api: APIClient {
        APIClient(config: config)
    }

    private func loadPrograms() async {
        isLoading = true
        error = nil
        do {
            let response = try await api.getPrograms()
            programs = response.programs
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func deleteProgram(_ program: ProgramResponse) async {
        do {
            try await api.deleteProgram(slug: program.slug)
            programs.removeAll { $0.slug == program.slug }
        } catch {
            self.error = error.localizedDescription
        }
        programToDelete = nil
    }
}

// MARK: - ProgramRow

struct ProgramRow: View {
    let program: ProgramResponse

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(program.icon)
                    Text(program.name)
                        .font(.headline)
                }
                HStack(spacing: 8) {
                    Text(program.slug)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fontDesign(.monospaced)
                    if let example = program.referenceExample {
                        Text(example)
                            .font(.caption)
                            .foregroundStyle(.blue)
                            .fontDesign(.monospaced)
                    }
                }
                if !program.capabilities.isEmpty {
                    Text(program.capabilities.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if program.isActive {
                Text("Active")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.green.opacity(0.15))
                    .foregroundStyle(.green)
                    .clipShape(Capsule())
            } else {
                Text("Inactive")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.15))
                    .foregroundStyle(.secondary)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - CreateProgramSheet

struct CreateProgramSheet: View {
    // MARK: Internal

    @EnvironmentObject var config: ServerConfig

    let onCreated: () async -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Required") {
                    TextField("Slug (e.g. pota)", text: $slug)
                        .textInputAutocapitalization(.never)
                        .fontDesign(.monospaced)
                    TextField("Name", text: $name)
                    TextField("Short Name", text: $shortName)
                    TextField("Icon (emoji)", text: $icon)
                    TextField("Reference Label", text: $referenceLabel)
                }

                Section("Optional") {
                    TextField("Website URL", text: $website)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                    TextField("Reference Format", text: $referenceFormat)
                        .fontDesign(.monospaced)
                    TextField("Reference Example", text: $referenceExample)
                        .fontDesign(.monospaced)
                    TextField("Sort Order", text: $sortOrder)
                        .keyboardType(.numberPad)
                }

                Section {
                    Toggle("Multi-Ref Allowed", isOn: $multiRefAllowed)
                    Toggle("Supports Rove", isOn: $supportsRove)
                }

                if let error {
                    Section {
                        Text(error).foregroundStyle(.red).font(.subheadline)
                    }
                }
            }
            .navigationTitle("New Program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await create() }
                    }
                    .disabled(slug.isEmpty || name.isEmpty || shortName.isEmpty || icon.isEmpty || referenceLabel
                        .isEmpty || isSubmitting)
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var slug = ""
    @State private var name = ""
    @State private var shortName = ""
    @State private var icon = ""
    @State private var website = ""
    @State private var referenceLabel = ""
    @State private var referenceFormat = ""
    @State private var referenceExample = ""
    @State private var multiRefAllowed = false
    @State private var supportsRove = false
    @State private var sortOrder = ""
    @State private var isSubmitting = false
    @State private var error: String?

    private func create() async {
        isSubmitting = true
        error = nil
        let api = APIClient(config: config)
        let request = CreateProgramRequest(
            slug: slug,
            name: name,
            shortName: shortName,
            icon: icon,
            website: website.isEmpty ? nil : website,
            referenceLabel: referenceLabel,
            referenceFormat: referenceFormat.isEmpty ? nil : referenceFormat,
            referenceExample: referenceExample.isEmpty ? nil : referenceExample,
            multiRefAllowed: multiRefAllowed,
            supportsRove: supportsRove,
            sortOrder: Int(sortOrder) ?? 0
        )
        do {
            _ = try await api.createProgram(request)
            await onCreated()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isSubmitting = false
    }
}

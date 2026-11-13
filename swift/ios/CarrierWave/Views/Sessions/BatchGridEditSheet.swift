import CarrierWaveData
import SwiftUI

// MARK: - BatchGridResult

/// Result type for batch grid editing — supports single grid or per-park grids.
enum BatchGridResult {
    /// Non-rove: one grid for all QSOs
    case uniform(String)
    /// Rove: parkReference → grid
    case perPark([String: String])
}

// MARK: - BatchGridEditSheet

/// Sheet for setting the grid square on all QSOs in a session.
/// For rove sessions, shows one field per park group.
struct BatchGridEditSheet: View {
    // MARK: Lifecycle

    init(
        currentGrid: String? = nil,
        parkGroups: [RoveParkGroup]? = nil,
        roveStopGrids: [String: String] = [:],
        onSave: @escaping (BatchGridResult) -> Void
    ) {
        self.parkGroups = parkGroups
        self.onSave = onSave
        _gridText = State(initialValue: currentGrid ?? "")
        _parkGrids = State(initialValue: roveStopGrids)
    }

    // MARK: Internal

    var body: some View {
        NavigationStack {
            Form {
                if let parkGroups {
                    roveFields(parkGroups)
                } else {
                    uniformField
                }
            }
            .navigationTitle("Set My Grid")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
        .landscapeAdaptiveDetents(portrait: [.medium])
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var gridText: String
    @State private var parkGrids: [String: String]

    private let parkGroups: [RoveParkGroup]?
    private let onSave: (BatchGridResult) -> Void

    private var isValid: Bool {
        if parkGroups != nil {
            return parkGrids.values.contains { MaidenheadConverter.isValid($0) }
        }
        return !gridText.isEmpty && MaidenheadConverter.isValid(gridText)
    }

    private var uniformField: some View {
        Section {
            TextField("Grid Square", text: $gridText)
                .font(.body.monospaced())
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
        } footer: {
            Text("This will update all QSOs in the session.")
        }
    }

    private func roveFields(_ groups: [RoveParkGroup]) -> some View {
        Section {
            ForEach(groups, id: \.parkReference) { group in
                let ref = group.parkReference
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ref)
                            .font(.subheadline.monospaced().weight(.semibold))
                        if let name = POTAParksCache.shared.nameSync(
                            for: group.primaryPark
                        ) {
                            Text(name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(minWidth: 80, alignment: .leading)

                    TextField("Grid", text: binding(for: ref))
                        .font(.body.monospaced())
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                }
            }
        } footer: {
            Text("Set a grid for each park. Empty fields are skipped.")
        }
    }

    private func binding(for parkRef: String) -> Binding<String> {
        Binding(
            get: { parkGrids[parkRef, default: ""] },
            set: { parkGrids[parkRef] = $0 }
        )
    }

    private func save() {
        if parkGroups != nil {
            let valid = parkGrids
                .filter { MaidenheadConverter.isValid($0.value) }
                .mapValues { $0.uppercased() }
            onSave(.perPark(valid))
        } else {
            onSave(.uniform(gridText.uppercased()))
        }
    }
}

import SwiftUI

// MARK: - P2PFilterSheet

/// Inline filter sheet for P2P spots. Band/mode are session-scoped (@Binding).
struct P2PFilterSheet: View {
    // MARK: Internal

    @Binding var selectedBands: Set<String>
    @Binding var selectedModes: Set<String>
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            Form {
                bandSection
                modeSection
            }
            .navigationTitle("Filter P2P")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        selectedBands = []
                        selectedModes = []
                    }
                }
            }
        }
        .landscapeAdaptiveDetents(portrait: [.medium])
    }

    // MARK: Private

    private static let selectableBands = BandFilter.allCases
        .filter { $0 != .all }
        .map(\.rawValue)

    private static let selectableModes = ModeFilter.allCases
        .filter { $0 != .all }

    // MARK: - Sections

    private var bandSection: some View {
        Section {
            ForEach(Self.selectableBands, id: \.self) { band in
                let isSelected = selectedBands.contains(band)
                Button {
                    toggleInSet(&selectedBands, value: band)
                } label: {
                    HStack {
                        Text(band)
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.orange)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Bands")
        } footer: {
            Text(
                selectedBands.isEmpty
                    ? "Showing all bands."
                    : "Showing \(selectedBands.count) band(s)."
            )
        }
    }

    private var modeSection: some View {
        Section {
            ForEach(Self.selectableModes, id: \.rawValue) { mode in
                let isSelected = selectedModes.contains(mode.rawValue)
                Button {
                    toggleInSet(&selectedModes, value: mode.rawValue)
                } label: {
                    HStack {
                        Text(mode.rawValue)
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.orange)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Modes")
        } footer: {
            Text(
                selectedModes.isEmpty
                    ? "Showing all modes."
                    : "Showing \(selectedModes.count) mode(s)."
            )
        }
    }

    private func toggleInSet(_ set: inout Set<String>, value: String) {
        if set.contains(value) {
            set.remove(value)
        } else {
            set.insert(value)
        }
    }
}

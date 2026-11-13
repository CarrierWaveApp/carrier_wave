import CarrierWaveData
import SwiftUI

// MARK: - HuntFilterSheet

/// Inline filter sheet for HUNT spots. Band/mode are session-scoped (@Binding).
/// Activity, club, and friend prefs live in Settings.
struct HuntFilterSheet: View {
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
            .navigationTitle("Filter Spots")
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
                                .foregroundStyle(.blue)
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
                                .foregroundStyle(.blue)
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

// MARK: - POTASpotsLoadingView

struct POTASpotsLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading spots...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
}

// MARK: - POTASpotsEmptyView

struct POTASpotsEmptyView: View {
    let hasFilters: Bool
    let onClearFilters: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tree")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No spots match filters")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if hasFilters {
                Button("Clear Filters", action: onClearFilters)
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 200)
    }
}

// MARK: - POTASpotsErrorView

struct POTASpotsErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry", action: onRetry)
                .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 200)
    }
}

// MARK: - POTASpotsBandHeader

struct POTASpotsBandHeader: View {
    let band: String

    var body: some View {
        HStack {
            Text(band)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemGroupedBackground))
    }
}

// MARK: - SOTASpotsBandHeader

struct SOTASpotsBandHeader: View {
    let band: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "mountain.2.fill")
                .font(.caption2)
                .foregroundStyle(.brown)
            Text("SOTA")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.brown)
            Text(band)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemGroupedBackground))
    }
}

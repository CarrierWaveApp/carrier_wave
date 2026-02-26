import SwiftUI

// MARK: - POTASpotsFilterSheet

/// Filter sheet for POTA spots view
struct POTASpotsFilterSheet: View {
    @Binding var bandFilter: BandFilter
    @Binding var modeFilter: ModeFilter
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Band") {
                    Picker("Band", selection: $bandFilter) {
                        ForEach(BandFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Mode") {
                    Picker("Mode", selection: $modeFilter) {
                        ForEach(ModeFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
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
                        bandFilter = .all
                        modeFilter = .all
                    }
                }
            }
        }
        .landscapeAdaptiveDetents(portrait: [.medium])
    }
}

// MARK: - POTASpotsLoadingView

/// Loading state view for spots
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

/// Empty state view for POTA spots
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

/// Error state view for POTA spots
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

/// Section header for POTA band grouping
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

/// Section header for SOTA band grouping with mountain icon and brown accent
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

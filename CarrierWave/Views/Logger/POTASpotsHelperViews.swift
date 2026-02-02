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
        .presentationDetents([.medium])
    }
}

// MARK: - AutomatedSpotsSection

/// Collapsible section for RBN automated spots
struct AutomatedSpotsSection: View {
    let automatedSpots: [POTASpot]
    let automatedSpotsByBand: [(band: String, spots: [POTASpot])]
    let userCallsign: String?
    let onSelectSpot: ((POTASpot) -> Void)?

    @Binding var isExpanded: Bool

    var body: some View {
        Section {
            // Collapsible header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    Text("RBN Automated Spots")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(automatedSpots.count)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.tertiarySystemGroupedBackground))
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                ForEach(automatedSpotsByBand, id: \.band) { section in
                    // Mini band header
                    HStack {
                        Text(section.band)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color(.quaternarySystemFill))

                    ForEach(section.spots) { spot in
                        POTASpotRow(spot: spot, userCallsign: userCallsign) {
                            onSelectSpot?(spot)
                        }
                        .opacity(0.7)
                        Divider()
                            .padding(.leading, 92)
                    }
                }
            }
        }
    }
}

// MARK: - POTASpotsLoadingView

/// Loading state view for POTA spots
struct POTASpotsLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading POTA spots...")
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

/// Section header for band grouping
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

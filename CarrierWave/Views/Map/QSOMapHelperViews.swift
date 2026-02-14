import MapKit
import SwiftUI

// MARK: - QSOMarkerView

struct QSOMarkerView: View {
    // MARK: Internal

    let annotation: QSOAnnotation
    var isSelected: Bool = false

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(markerColor)
                    .frame(width: markerSize, height: markerSize)
                    .overlay(
                        Circle()
                            .stroke(isSelected ? Color.white : Color.clear, lineWidth: 3)
                    )

                if annotation.qsoCount > 1 {
                    Text("\(annotation.qsoCount)")
                        .font(.system(size: fontSize, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .shadow(radius: isSelected ? 4 : 2)
            .scaleEffect(isSelected ? 1.2 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
    }

    // MARK: Private

    private var markerSize: CGFloat {
        switch annotation.qsoCount {
        case 1: 12
        case 2 ... 5: 28
        case 6 ... 20: 36
        default: 44
        }
    }

    private var fontSize: CGFloat {
        switch annotation.qsoCount {
        case 1 ... 5: 10
        case 6 ... 99: 12
        default: 10
        }
    }

    private var markerColor: Color {
        switch annotation.qsoCount {
        case 1: .blue
        case 2 ... 5: .green
        case 6 ... 20: .orange
        default: .red
        }
    }
}

// MARK: - MapFilterSheet

struct MapFilterSheet: View {
    // MARK: Internal

    @Bindable var filterState: MapFilterState

    let availableBands: [String]
    let availableModes: [String]
    let availableParks: [String]
    let earliestDate: Date?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "From",
                        selection: Binding(
                            get: { filterState.startDate ?? earliestDate ?? Date() },
                            set: { filterState.startDate = $0 }
                        ),
                        displayedComponents: .date
                    )

                    DatePicker(
                        "To",
                        selection: Binding(
                            get: { filterState.endDate ?? Date() },
                            set: { filterState.endDate = $0 }
                        ),
                        displayedComponents: .date
                    )

                    if filterState.startDate != nil || filterState.endDate != nil {
                        Button("Clear Date Range") {
                            filterState.startDate = nil
                            filterState.endDate = nil
                        }
                    }
                } header: {
                    Text("Date Range")
                }

                Section {
                    Picker("Band", selection: $filterState.selectedBand) {
                        Text("All Bands").tag(String?.none)
                        ForEach(availableBands, id: \.self) { band in
                            Text(band).tag(String?.some(band))
                        }
                    }

                    Picker("Mode", selection: $filterState.selectedMode) {
                        Text("All Modes").tag(String?.none)
                        ForEach(availableModes, id: \.self) { mode in
                            Text(mode).tag(String?.some(mode))
                        }
                    }

                    if !availableParks.isEmpty {
                        Picker("Park", selection: $filterState.selectedPark) {
                            Text("All Parks").tag(String?.none)
                            ForEach(availableParks, id: \.self) { park in
                                Text(park).tag(String?.some(park))
                            }
                        }
                    }
                } header: {
                    Text("Filters")
                }

                Section {
                    Toggle("Confirmed Only", isOn: $filterState.confirmedOnly)
                }

                Section {
                    Toggle("Show Individual QSOs", isOn: $filterState.showIndividualQSOs)
                    Toggle("Show Paths", isOn: $filterState.showPaths)
                } header: {
                    Text("Display")
                } footer: {
                    Text(
                        """
                        Individual QSOs shows each contact as a small dot. \
                        Paths draw geodesic curves to contacted stations.
                        """
                    )
                }

                Section {
                    Toggle("Show All QSOs", isOn: $filterState.showAllQSOs)
                } header: {
                    Text("Performance")
                } footer: {
                    if filterState.showAllQSOs {
                        Text(
                            "Warning: Showing all QSOs may cause the app to become unresponsive with large datasets."
                        )
                        .foregroundStyle(.orange)
                    } else {
                        Text(
                            "Limited to \(MapFilterState.maxQSOsDefault) QSOs for performance. Enable to show all."
                        )
                    }
                }

                if filterState.hasActiveFilters {
                    Section {
                        Button("Reset All Filters", role: .destructive) {
                            filterState.resetFilters()
                        }
                    }
                }
            }
            .navigationTitle("Map Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
}

// MARK: - QSOCalloutView

struct QSOCalloutView: View {
    // MARK: Internal

    let annotation: QSOAnnotation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(annotation.gridSquare)
                .font(.headline)

            Text("\(annotation.qsoCount) QSO\(annotation.qsoCount == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !annotation.callsigns.isEmpty {
                Text(annotation.callsigns.prefix(5).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if hasActivationMetadata {
                Divider()
                activationMetadataSection
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Private

    private var hasActivationMetadata: Bool {
        !annotation.parkReferences.isEmpty
            && (annotation.weather != nil || annotation.solarConditions != nil
                || annotation.averageWPM != nil || hasEquipment)
    }

    private var hasEquipment: Bool {
        annotation.radio != nil || annotation.antenna != nil
            || annotation.key != nil || annotation.mic != nil
    }

    private var activationMetadataSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(annotation.parkReferences.sorted()), id: \.self) { park in
                Label(park, systemImage: "leaf")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            if let wpm = annotation.averageWPM {
                Label("\(wpm) WPM avg", systemImage: "gauge.medium")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let radio = annotation.radio {
                Label(radio, systemImage: "radio")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let antenna = annotation.antenna {
                Label(antenna, systemImage: "antenna.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let key = annotation.key {
                Label(key, systemImage: "pianokeys")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let mic = annotation.mic {
                Label(mic, systemImage: "mic")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let weather = annotation.weather, !weather.isEmpty {
                Label(weather, systemImage: "cloud")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let solar = annotation.solarConditions, !solar.isEmpty {
                Label(solar, systemImage: "sun.max")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - MapStatsOverlay

struct MapStatsOverlay: View {
    // MARK: Internal

    let totalQSOs: Int
    let visibleQSOs: Int
    let gridCount: Int
    let stateCount: Int
    let dxccCount: Int
    let statistics: MapStatistics

    var body: some View {
        // swiftlint:disable:next redundant_discardable_let
        let _ = useMetricUnits // Trigger re-render when unit preference changes
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                statItem(value: visibleQSOs, label: "QSOs")
                statItem(value: gridCount, label: "Grids")
                statItem(value: stateCount, label: "States")
                statItem(value: dxccCount, label: "DXCC")
            }

            HStack(spacing: 10) {
                statItem(
                    text: statistics.averageDistanceKm.map {
                        UnitFormatter.distanceCompact($0)
                    } ?? "--",
                    label: "Avg"
                )
                statItem(
                    text: statistics.longestDistanceKm.map {
                        UnitFormatter.distanceCompact($0)
                    } ?? "--",
                    label: "Max"
                )
                if statistics.wattsPerMile != nil {
                    let wpmValue = statistics.wattsPerMile.map { wpm -> String in
                        let display = UnitFormatter.useMetric ? wpm * 0.621371 : wpm
                        return String(format: "%.2f", display)
                    }
                    statItem(
                        text: wpmValue ?? "--",
                        label: UnitFormatter.wattsPerDistanceLabel()
                    )
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Private

    @AppStorage("useMetricUnits") private var useMetricUnits = false

    private func statItem(value: Int, label: String) -> some View {
        statItem(text: "\(value)", label: label)
    }

    private func statItem(text: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(text)
                .font(.headline)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3_600
        let minutes = (Int(duration) % 3_600) / 60
        if hours > 0 {
            return "\(hours)h\(minutes)m"
        }
        return "\(minutes)m"
    }
}

// MARK: - ActiveFiltersView

struct ActiveFiltersView: View {
    // MARK: Internal

    @Bindable var filterState: MapFilterState

    let earliestDate: Date?
    let latestDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Date filters always at the top
            FilterChip(label: "From: \(formatDate(displayStartDate))", icon: "calendar")
            FilterChip(label: "To: \(formatDate(displayEndDate))", icon: "calendar")

            // Other filters below (only when active)
            if let band = filterState.selectedBand {
                FilterChip(label: band, icon: "waveform")
            }
            if let mode = filterState.selectedMode {
                FilterChip(label: mode, icon: "dot.radiowaves.left.and.right")
            }
            if let park = filterState.selectedPark {
                FilterChip(label: park, icon: "leaf")
            }
            if filterState.confirmedOnly {
                FilterChip(label: "Confirmed", icon: "checkmark.seal")
            }
        }
        .padding(8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Private

    private var displayStartDate: Date {
        filterState.startDate ?? earliestDate ?? latestDate
    }

    private var displayEndDate: Date {
        filterState.endDate ?? latestDate
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - FilterChip

struct FilterChip: View {
    let label: String
    let icon: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.blue.opacity(0.2))
        .foregroundStyle(.blue)
        .clipShape(Capsule())
    }
}

import CarrierWaveCore
import SwiftData
import SwiftUI

// MARK: - SpotListView

/// Spot list showing live POTA/RBN/SOTA/WWFF/Cluster spots from SpotAggregator
struct SpotListView: View {
    // MARK: Internal

    var initialSourceFilter: SpotSourceFilter = .all

    var body: some View {
        VStack(spacing: 0) {
            header
            filterBar
            Divider()

            if cachedFilteredSpots.isEmpty {
                emptyState
            } else {
                spotTable
            }
        }
        .task(id: initialSourceFilter) {
            selectedSource = initialSourceFilter
        }
        .onChange(of: selectedSource) { refilter() }
        .onChange(of: selectedBand) { refilter() }
        .onChange(of: selectedMode) { refilter() }
        .onChange(of: selectedRegionGroup) { refilter() }
        .onChange(of: filterText) { refilter() }
        .onChange(of: spotAggregator.spots.count) { refilter() }
        .onAppear { refilter() }
    }

    // MARK: Private

    @Environment(SpotAggregator.self) private var spotAggregator
    @Environment(RadioManager.self) private var radioManager
    @Environment(TuneInManager.self) private var tuneInManager
    @Environment(SelectionState.self) private var selectionState
    @Environment(\.modelContext) private var modelContext
    @State private var filterText = ""
    @State private var selectedSource: SpotSourceFilter = .all
    @State private var selectedBand: String = "All"
    @State private var selectedMode: SpotModeFilter = .all
    @State private var selectedRegionGroup: SpotRegionGroup?
    @AppStorage("autoXITEnabled") private var autoXITEnabled = false
    @AppStorage("autoXITOffsetHz") private var autoXITOffsetHz = 0
    @State private var selection: Set<EnrichedSpot.ID> = []
    @State private var cachedFilteredSpots: [EnrichedSpot] = []

    // MARK: - Helpers

    private let commonBands = ["160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m", "6m"]

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Spots")
                .font(.headline)

            if let lastRefresh = spotAggregator.lastRefresh {
                Text(lastRefresh, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Spot counts by source
            HStack(spacing: 8) {
                ForEach(SpotSource.allCases, id: \.rawValue) { source in
                    let count = spotAggregator.spotCounts[source] ?? 0
                    if count > 0 {
                        HStack(spacing: 2) {
                            Circle()
                                .fill(sourceColor(source))
                                .frame(width: 6, height: 6)
                                .accessibilityHidden(true)
                            Text("\(count)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(source.displayName): \(count) spots")
                    }
                }
            }

            Button {
                Task { await spotAggregator.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Refresh spots")
            .help("Refresh spots")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 6) {
            // Source filter
            Picker(selection: $selectedSource) {
                ForEach(SpotSourceFilter.allCases) { source in
                    Text(source.displayName).tag(source)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .frame(width: 320)

            // Band filter
            Picker("Band", selection: $selectedBand) {
                Text("All").tag("All")
                ForEach(commonBands, id: \.self) { band in
                    Text(band).tag(band)
                }
            }
            .labelsHidden()
            .frame(width: 75)

            // Mode filter
            Picker(selection: $selectedMode) {
                ForEach(SpotModeFilter.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

            // Region filter
            Picker("Region", selection: $selectedRegionGroup) {
                Text("All Regions").tag(SpotRegionGroup?.none)
                ForEach(SpotRegionGroup.allCases, id: \.rawValue) { group in
                    Text(group.rawValue).tag(SpotRegionGroup?.some(group))
                }
            }
            .labelsHidden()
            .frame(width: 110)

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter...", text: $filterText)
                    .textFieldStyle(.plain)
                if !filterText.isEmpty {
                    Button {
                        filterText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear filter")
                }
            }
            .frame(minWidth: 100)
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 32))
                .foregroundStyle(.quaternary)
            if spotAggregator.isPolling, spotAggregator.spots.isEmpty {
                Text("Loading spots...")
                    .foregroundStyle(.secondary)
                ProgressView()
            } else if filterText.isEmpty, selectedSource == .all {
                Text("No spots loaded")
                    .foregroundStyle(.secondary)
                Text("Spots will appear when polling starts")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Text("No spots matching filters")
                    .foregroundStyle(.secondary)
            }

            // Show errors
            if !spotAggregator.errors.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(spotAggregator.errors), id: \.key) { source, message in
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.yellow)
                            Text("\(source.displayName): \(message)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 8)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Spot Table

    private var spotTable: some View {
        Table(of: EnrichedSpot.self, selection: $selection) {
            TableColumn("Age") { spot in
                Text(spot.spot.timeAgo)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(ageColor(spot.spot.timestamp))
            }
            .width(min: 30, ideal: 45)

            TableColumn("Source") { spot in
                Text(spot.spot.source.displayName)
                    .font(.caption2)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(sourceColor(spot.spot.source).opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .width(min: 40, ideal: 50)

            TableColumn("Callsign") { spot in
                Text(spot.spot.callsign)
                    .fontWeight(.medium)
            }
            .width(min: 80, ideal: 100)

            TableColumn("Freq") { spot in
                Text(String(format: "%.1f", spot.spot.frequencyKHz))
                    .monospacedDigit()
            }
            .width(min: 60, ideal: 80)

            TableColumn("Mode") { spot in
                Text(spot.spot.mode)
                    .font(.caption)
            }
            .width(min: 40, ideal: 50)

            TableColumn("Reference") { spot in
                Text(spot.spot.referenceDisplay ?? "—")
                    .foregroundStyle(spot.spot.referenceDisplay != nil ? Color.accentColor : Color.secondary)
            }
            .width(min: 60, ideal: 80)

            TableColumn("Name") { spot in
                Text(spot.spot.locationDisplay ?? "—")
                    .foregroundStyle(spot.spot.locationDisplay != nil ? Color.primary : Color.secondary)
                    .lineLimit(1)
            }
            .width(min: 80, ideal: 120)

            TableColumn("Dist / Brg") { spot in
                Text(spot.formattedDistanceAndBearing() ?? "—")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .width(min: 70, ideal: 90)

            TableColumn("Location") { spot in
                Text(spot.locationDisplay ?? spot.region.shortName)
                    .font(.caption)
                    .foregroundStyle(spot.locationDisplay != nil ? .primary : .secondary)
            }
            .width(min: 40, ideal: 55)

            TableColumn("Spotter") { spot in
                Text(spot.spot.spotter ?? "—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 80)
        } rows: {
            ForEach(cachedFilteredSpots) { spot in
                TableRow(spot)
                    .contextMenu {
                        Button("Tune & Log") {
                            tuneAndLog(spot)
                        }
                        Button("Tune In (SDR)") {
                            tuneInToSDR(spot)
                        }
                        Button("Lookup \(spot.spot.callsign)") {}
                    }
            }
        }
        .alternatingRowBackgrounds()
        .onChange(of: selection) { _, newSelection in
            if let selectedId = newSelection.first {
                selectionState.selectedSpot = cachedFilteredSpots.first { $0.id == selectedId }
                selectionState.selectedQSOId = nil
            } else {
                selectionState.selectedSpot = nil
            }
        }
        .onKeyPress(.return) {
            guard let selectedId = selection.first,
                  let spot = cachedFilteredSpots.first(where: { $0.id == selectedId })
            else {
                return .ignored
            }
            tuneAndLog(spot)
            return .handled
        }
    }
}

// MARK: - SpotListView + Filtering & Actions

extension SpotListView {
    func refilter() {
        var result = spotAggregator.spots

        // Source filter
        if selectedSource != .all {
            result = result.filter { $0.spot.source.rawValue == selectedSource.rawValue }
        }

        // Band filter
        if selectedBand != "All" {
            result = result.filter { $0.spot.band == selectedBand }
        }

        // Mode filter
        if selectedMode != .all {
            result = result.filter { selectedMode.matches(mode: $0.spot.mode) }
        }

        // Region filter
        if let group = selectedRegionGroup {
            result = result.filter { $0.region.group == group }
        }

        // Text filter
        if !filterText.isEmpty {
            let query = filterText.lowercased()
            result = result.filter {
                $0.spot.callsign.lowercased().contains(query) ||
                    ($0.spot.referenceDisplay?.lowercased().contains(query) ?? false) ||
                    ($0.spot.locationDisplay?.lowercased().contains(query) ?? false) ||
                    ($0.spot.spotter?.lowercased().contains(query) ?? false) ||
                    ($0.spot.comments?.lowercased().contains(query) ?? false)
            }
        }

        cachedFilteredSpots = result
    }

    func ageColor(_ date: Date) -> Color {
        let minutes = Date().timeIntervalSince(date) / 60
        if minutes < 5 {
            return Color(nsColor: .systemGreen)
        }
        if minutes < 15 {
            return .primary
        }
        return .secondary
    }

    func sourceColor(_ source: SpotSource) -> Color {
        switch source {
        case .rbn: .blue
        case .pota: .green
        case .sota: .orange
        case .wwff: .teal
        case .cluster: .yellow
        }
    }

    func tuneAndLog(_ spot: EnrichedSpot) {
        let freqStr = String(format: "%.3f", spot.spot.frequencyMHz)
        selectionState.pendingSpotEntry = "\(spot.spot.callsign) \(freqStr)"
        selectionState.selectedSpot = spot
        selectionState.selectedQSOId = nil
        Task {
            try? await radioManager.tuneToFrequency(spot.spot.frequencyMHz)
            try? await radioManager.setMode(spot.spot.mode)
            if autoXITEnabled, autoXITOffsetHz != 0 {
                try? await radioManager.setXITOffset(autoXITOffsetHz)
                try? await radioManager.setXIT(true)
            } else if autoXITEnabled {
                try? await radioManager.setXIT(false)
            }
        }
    }

    func tuneInToSDR(_ spot: EnrichedSpot) {
        let tuneInSpot = TuneInSpot(from: spot)
        Task {
            await tuneInManager.tuneIn(
                to: tuneInSpot,
                modelContext: modelContext
            )
        }
    }
}

// MARK: - SpotSourceFilter

enum SpotSourceFilter: String, CaseIterable, Identifiable {
    case all
    case pota
    case rbn
    case sota
    case wwff
    case cluster

    // MARK: Internal

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .all: "All"
        case .pota: "POTA"
        case .rbn: "RBN"
        case .sota: "SOTA"
        case .wwff: "WWFF"
        case .cluster: "Cluster"
        }
    }
}

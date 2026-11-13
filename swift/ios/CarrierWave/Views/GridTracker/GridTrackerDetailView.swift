//
//  GridTrackerDetailView.swift
//  CarrierWave
//
//  Full grid tracker view with interactive heatmap, statistics, and grid list.
//

import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - GridTrackerDetailView

struct GridTrackerDetailView: View {
    // MARK: Internal

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let summary {
                    statsSection(summary: summary)
                    heatmapSection(summary: summary)
                    gridListSection(summary: summary)
                } else {
                    loadingView
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Grid Tracker")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search grids...")
        .task {
            await loadData()
        }
        // Debounce keyboard input so the filter+sort runs once per typing
        // burst, not per keystroke. 150 ms feels instant but coalesces.
        .task(id: searchText) {
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else {
                return
            }
            debouncedSearchText = searchText
        }
        // Recompute the filtered list off-the-body whenever an input
        // actually changes. Keeping `filteredGrids(...)` out of `body`
        // is what makes the keyboard responsive — body re-evaluates on
        // every keystroke (because `searchText` is bound to `.searchable`),
        // so any expensive work called from `body` blocks input even
        // after the work has stopped logically depending on `searchText`.
        .onChange(of: debouncedSearchText) { _, _ in recomputeFilteredGrids() }
        .onChange(of: selectedField) { _, _ in recomputeFilteredGrids() }
        .onChange(of: sortOrder) { _, _ in recomputeFilteredGrids() }
        .onChange(of: summary?.totalGridsWorked) { _, _ in recomputeFilteredGrids() }
    }

    // MARK: Private

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var summary: GridTrackerSummary?
    @State private var selectedField: String?
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var sortOrder: GridSortOrder = .qsoCount
    @State private var filteredGridsCache: [GridSquareData] = []

    private func recomputeFilteredGrids() {
        guard let summary else {
            filteredGridsCache = []
            return
        }
        filteredGridsCache = filteredGrids(from: summary)
    }
}

// MARK: - Stats Section

extension GridTrackerDetailView {
    private var statsGridColumns: [GridItem] {
        if horizontalSizeClass == .regular {
            Array(repeating: GridItem(.flexible()), count: 6)
        } else {
            Array(repeating: GridItem(.flexible()), count: 3)
        }
    }

    private func statsSection(summary: GridTrackerSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overview")
                .font(.headline)

            LazyVGrid(columns: statsGridColumns, spacing: 12) {
                gridStatBox(
                    title: "Grids",
                    value: "\(summary.totalGridsWorked)",
                    icon: "square.grid.3x3"
                )
                gridStatBox(
                    title: "Confirmed",
                    value: "\(summary.totalGridsConfirmed)",
                    icon: "checkmark.seal"
                )
                gridStatBox(
                    title: "Fields",
                    value: "\(summary.totalFields)",
                    icon: "globe"
                )
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func gridStatBox(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .accessibilityHidden(true)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Heatmap Section

extension GridTrackerDetailView {
    private func heatmapSection(summary: GridTrackerSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Grid Map")
                    .font(.headline)
                Spacer()
                if selectedField != nil {
                    Button {
                        self.selectedField = nil
                    } label: {
                        Text("Clear")
                            .font(.caption)
                    }
                    .accessibilityLabel("Clear field selection")
                }
            }

            GridHeatmapView(summary: summary, compact: false) { grid in
                selectedField = String(grid.prefix(2))
            }
            // Stops the Canvas from redrawing ~32 000 cells on every
            // keystroke in the search field — see GridHeatmapView's
            // Equatable conformance.
            .equatable()
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Grid List Section

extension GridTrackerDetailView {
    private func gridListSection(summary _: GridTrackerSummary) -> some View {
        // Read the precomputed cache (recomputed off-body via .onChange).
        // Body re-evaluates on every keystroke because `searchText` is
        // bound to `.searchable`, so anything expensive called from `body`
        // blocks the keyboard.
        let grids = filteredGridsCache
        let lastGridId = grids.last?.grid
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Worked Grids")
                    .font(.headline)

                Spacer()

                sortPicker
            }

            LazyVStack(spacing: 0) {
                ForEach(grids, id: \.grid) { data in
                    gridRow(data: data)

                    if data.grid != lastGridId {
                        Divider()
                            .padding(.leading, 44)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var sortPicker: some View {
        Menu {
            ForEach(GridSortOrder.allCases, id: \.self) { order in
                Button {
                    sortOrder = order
                } label: {
                    if sortOrder == order {
                        Label(order.label, systemImage: "checkmark")
                    } else {
                        Text(order.label)
                    }
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
                .font(.caption)
        }
        .accessibilityLabel("Sort order: \(sortOrder.label)")
    }

    private func filteredGrids(from summary: GridTrackerSummary) -> [GridSquareData] {
        var grids = Array(summary.gridData.values)

        // Apply field filter
        if let selectedField {
            grids = grids.filter { $0.grid.hasPrefix(selectedField) }
        }

        // Apply search filter using the debounced text so we don't filter
        // and sort on every keystroke.
        let trimmed = debouncedSearchText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            // `range(of:options:.caseInsensitive)` avoids the per-callsign
            // `String.uppercased()` allocation that the previous form did
            // inside a hot O(grids × callsigns) inner loop.
            let opts: String.CompareOptions = .caseInsensitive
            grids = grids.filter { data in
                data.grid.range(of: trimmed, options: opts) != nil
                    || data.callsigns.contains { $0.range(of: trimmed, options: opts) != nil }
            }
        }

        // Sort
        switch sortOrder {
        case .qsoCount:
            grids.sort { $0.qsoCount > $1.qsoCount }
        case .alphabetical:
            grids.sort { $0.grid < $1.grid }
        case .recent:
            grids.sort { lhs, rhs in
                (lhs.mostRecent ?? .distantPast) > (rhs.mostRecent ?? .distantPast)
            }
        }

        return grids
    }

    private func gridRow(data: GridSquareData) -> some View {
        HStack(spacing: 12) {
            gridStatusIndicator(data: data)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(data.grid)
                        .font(.subheadline.weight(.semibold).monospaced())

                    if data.confirmedCount > 0 {
                        Text("QSL")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .foregroundStyle(Color(.systemBackground))
                            .background(Color.green)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }

                HStack(spacing: 4) {
                    Text("\(data.qsoCount) QSO\(data.qsoCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !data.bands.isEmpty {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(data.bands.sorted().joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                if let description = gridDescription(for: data.grid), !description.isEmpty {
                    Text(description)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if let mostRecent = data.mostRecent {
                Text(mostRecent, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(data.grid), \(data.qsoCount) QSOs\(data.confirmedCount > 0 ? ", confirmed" : "")"
        )
    }

    private func gridStatusIndicator(data: GridSquareData) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(data.confirmedCount > 0 ? Color.green.opacity(0.2) : Color.blue.opacity(0.2))
                .frame(width: 28, height: 28)

            Text(String(data.grid.prefix(2)))
                .font(.caption2.weight(.medium).monospaced())
                .foregroundStyle(data.confirmedCount > 0 ? .green : .blue)
        }
    }

    private func gridDescription(for grid: String) -> String? {
        let desc = DescriptionLookup.gridDescription(for: grid)
        return desc.isEmpty ? nil : desc
    }
}

// MARK: - Data Loading

extension GridTrackerDetailView {
    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Computing grid data...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private func loadData() async {
        do {
            let result = try await GridSummaryLoader.load()
            await MainActor.run {
                summary = result
            }
        } catch {
            await MainActor.run {
                summary = .empty
            }
        }
    }
}

// MARK: - GridSortOrder

enum GridSortOrder: String, CaseIterable {
    case qsoCount
    case alphabetical
    case recent

    // MARK: Internal

    var label: String {
        switch self {
        case .qsoCount: "QSO Count"
        case .alphabetical: "Grid Square"
        case .recent: "Most Recent"
        }
    }
}

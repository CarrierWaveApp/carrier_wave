//
//  GridTrackerCard.swift
//  CarrierWave
//
//  Dashboard card showing a mini grid heatmap with worked/confirmed counts.
//

import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - GridTrackerCard

struct GridTrackerCard: View {
    // MARK: Internal

    /// Generation counter from parent — only reload when data actually changes.
    var dataGeneration: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow

            if let summary, summary.totalGridsWorked > 0 {
                GridHeatmapView(summary: summary, compact: true)

                statsRow(summary: summary)
            } else if summary == nil {
                loadingPlaceholder
            } else {
                emptyState
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task(id: dataGeneration) {
            // .task re-fires on every tab switch — guard against redundant loads.
            // Only recompute when data generation changes (new QSOs logged/synced).
            guard !hasLoaded || dataGeneration != loadedGeneration else {
                return
            }
            // Debounce: skip if last load was less than 10s ago
            let now = Date()
            guard hasLoaded == false
                || now.timeIntervalSince(lastLoadTime) >= 10
            else {
                return
            }
            hasLoaded = true
            loadedGeneration = dataGeneration
            lastLoadTime = now
            await loadGridData()
        }
    }

    // MARK: Private

    @State private var summary: GridTrackerSummary?
    @State private var hasLoaded = false
    @State private var loadedGeneration: Int = -1
    @State private var lastLoadTime: Date = .distantPast

    // MARK: - Subviews

    private var headerRow: some View {
        HStack {
            Text("Grid Tracker")
                .font(.headline)

            Spacer()

            if let summary {
                Text("\(summary.totalGridsWorked) worked")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray5))
                .frame(height: 60)
            HStack(spacing: 16) {
                ForEach(0 ..< 3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 24)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .opacity(0.6)
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.grid.3x3")
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Log QSOs with grid squares to see your grid tracker")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statsRow(summary: GridTrackerSummary) -> some View {
        HStack(spacing: 16) {
            statItem(
                value: "\(summary.totalGridsWorked)",
                label: "Grids",
                color: .blue
            )
            statItem(
                value: "\(summary.totalGridsConfirmed)",
                label: "Confirmed",
                color: .green
            )
            statItem(
                value: "\(summary.totalFields)",
                label: "Fields",
                color: .blue
            )
        }
    }

    private func statItem(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Data Loading

    private func loadGridData() async {
        let profiler = StartupProfiler.shared
        profiler.record("gridTracker.load.start")
        let result = try? await GridSummaryLoader.load()
        summary = result ?? .empty
        profiler.record("gridTracker.load.done")
    }
}

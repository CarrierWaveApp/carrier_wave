//
//  AzimuthalStandaloneView.swift
//  CarrierWave
//
//  Standalone azimuthal map view accessible from the Map tab.
//  Resolves the operator's grid, loads spots from all sources and recent QSOs,
//  and passes them to the AzimuthalContainerView.
//

import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - AzimuthalStandaloneView

struct AzimuthalStandaloneView: View {
    // MARK: Internal

    var body: some View {
        Group {
            if let grid = resolvedGrid {
                AzimuthalContainerView(
                    myGrid: grid,
                    spots: spots,
                    sessionQSOs: qsos,
                    sessionAntenna: nil,
                    isLoadingSpots: isLoadingSpots
                )
            } else if gridService.isLocating {
                ProgressView("Locating...")
            } else {
                gridPromptView
            }
        }
        .navigationTitle("Azimuthal")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if resolvedGrid == nil {
                resolveGridFromKnownSources()
            }
            if resolvedGrid == nil {
                gridService.requestGrid()
            }
            if let grid = resolvedGrid {
                await loadData(grid: grid)
            }
        }
        .onChange(of: gridService.currentGrid) { _, newGrid in
            if let newGrid {
                resolvedGrid = newGrid
                Task { await loadData(grid: newGrid) }
            }
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext

    @AppStorage("loggerDefaultGrid") private var defaultGrid = ""
    @State private var gridService = GridLocationService()
    @State private var resolvedGrid: String?
    @State private var spots: [UnifiedSpot] = []
    @State private var qsos: [QSO] = []
    @State private var isLoadingSpots = false

    private var gridPromptView: some View {
        ContentUnavailableView {
            Label("Location Required", systemImage: "location.slash")
        } description: {
            Text("The azimuthal view needs your location to show spots and QSOs by bearing.")
        } actions: {
            Button("Get Location") {
                gridService.requestGrid()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func loadData(grid _: String) async {
        await loadRecentQSOs()
        await loadAllSpots()
    }

    private func loadRecentQSOs() async {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        var descriptor = FetchDescriptor<QSO>(
            predicate: #Predicate<QSO> { qso in
                qso.timestamp >= cutoff && qso.theirGrid != nil
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 500

        do {
            qsos = try modelContext.fetch(descriptor)
        } catch {
            qsos = []
        }
    }

    private func loadAllSpots() async {
        isLoadingSpots = true
        defer { isLoadingSpots = false }

        let cutoff = Date().addingTimeInterval(-30 * 60)

        // Fetch from all sources concurrently
        async let rbnResult = fetchRBNSpots(since: cutoff)
        async let potaResult = fetchPOTASpots(since: cutoff)
        async let sotaResult = fetchSOTASpots(since: cutoff)
        async let wwffResult = fetchWWFFSpots(since: cutoff)

        var allSpots = await rbnResult + potaResult + sotaResult + wwffResult

        // Enrich with callsign grids from HamDB for map projection
        allSpots = await enrichCallsignGrids(allSpots)

        spots = allSpots.sorted { $0.timestamp > $1.timestamp }
    }

    /// Check saved default grid and most recent session grid before falling back to GPS
    private func resolveGridFromKnownSources() {
        var descriptor = FetchDescriptor<LoggingSession>(
            sortBy: [SortDescriptor(\LoggingSession.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        if let session = try? modelContext.fetch(descriptor).first,
           let sessionGrid = session.myGrid, !sessionGrid.isEmpty
        {
            resolvedGrid = sessionGrid
            return
        }
        if !defaultGrid.isEmpty {
            resolvedGrid = defaultGrid
        }
    }
}

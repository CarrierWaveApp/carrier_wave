//
//  AzimuthalStandaloneView.swift
//  CarrierWave
//
//  Standalone azimuthal map view accessible from the Map tab.
//  Resolves the operator's grid via GPS, loads spots and recent QSOs,
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
                    sessionAntenna: nil
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
                gridService.requestGrid()
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

    @State private var gridService = GridLocationService()
    @State private var resolvedGrid: String?
    @State private var spots: [UnifiedSpot] = []
    @State private var qsos: [QSO] = []
    @State private var spotsService = SpotsService(
        rbnClient: RBNClient(),
        potaClient: POTAClient(authService: POTAAuthService())
    )

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

    private func loadData(grid: String) async {
        await loadRecentQSOs(grid: grid)
        await loadSpots(grid: grid)
    }

    private func loadRecentQSOs(grid: String) async {
        // Load QSOs from the last 30 days that have grid data
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

    private func loadSpots(grid: String) async {
        // Use the callsign from the most recent active session, or fall back
        let callsign = await resolveCallsign()
        guard let callsign else {
            return
        }

        do {
            spots = try await spotsService.fetchSpots(for: callsign, minutes: 30)
        } catch {
            // Non-fatal — show whatever we have
        }
    }

    private func resolveCallsign() async -> String? {
        // Try to get callsign from most recent session
        var descriptor = FetchDescriptor<LoggingSession>(
            sortBy: [SortDescriptor(\LoggingSession.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        let sessions = try? modelContext.fetch(descriptor)
        return sessions?.first?.myCallsign
    }
}

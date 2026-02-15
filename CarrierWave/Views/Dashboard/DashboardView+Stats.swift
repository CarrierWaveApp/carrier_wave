import SwiftUI

// MARK: - DashboardView Stats Grid Extension

extension DashboardView {
    var statsGrid: some View {
        LazyVGrid(columns: statsGridColumns, spacing: 12) {
            // QSOs - instant stat (always available)
            Button {
                selectedTab = .logs
            } label: {
                StatBox(
                    title: "QSOs",
                    value: "\(asyncStats.totalQSOs)",
                    icon: "antenna.radiowaves.left.and.right"
                )
            }
            .buttonStyle(.plain)

            // QSLs - deferred stat
            if let stats = asyncStats.getStats(), asyncStats.confirmedQSLs != nil {
                NavigationLink {
                    StatDetailView(
                        category: .qsls, items: stats.items(for: .qsls), tourState: tourState
                    )
                } label: {
                    StatBoxDeferred(
                        title: "QSLs", value: asyncStats.confirmedQSLs, icon: "checkmark.seal"
                    )
                }
                .buttonStyle(.plain)
            } else {
                StatBoxDeferred(
                    title: "QSLs", value: asyncStats.confirmedQSLs, icon: "checkmark.seal"
                )
            }

            // DXCC Entities - deferred stat, requires LoTW configured
            if lotwIsConfigured {
                if let stats = asyncStats.getStats(), asyncStats.uniqueEntities != nil {
                    NavigationLink {
                        StatDetailView(
                            category: .entities, items: stats.items(for: .entities),
                            tourState: tourState
                        )
                    } label: {
                        StatBoxDeferred(
                            title: "DXCC Entities", value: asyncStats.uniqueEntities, icon: "globe"
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    StatBoxDeferred(
                        title: "DXCC Entities", value: asyncStats.uniqueEntities, icon: "globe"
                    )
                }
            } else {
                StatBox(title: "DXCC Entities", value: "--", icon: "globe")
                    .opacity(0.5)
            }

            // Grids - instant stat
            if let stats = asyncStats.getStats() {
                NavigationLink {
                    StatDetailView(
                        category: .grids, items: stats.items(for: .grids), tourState: tourState
                    )
                } label: {
                    StatBox(
                        title: "Grids", value: "\(asyncStats.uniqueGrids)", icon: "square.grid.3x3"
                    )
                }
                .buttonStyle(.plain)
            } else {
                StatBox(title: "Grids", value: "\(asyncStats.uniqueGrids)", icon: "square.grid.3x3")
            }

            // Bands - instant stat
            if let stats = asyncStats.getStats() {
                NavigationLink {
                    StatDetailView(
                        category: .bands, items: stats.items(for: .bands), tourState: tourState
                    )
                } label: {
                    StatBox(
                        title: "Bands", value: "\(asyncStats.uniqueBands)", icon: "waveform"
                    )
                }
                .buttonStyle(.plain)
            } else {
                StatBox(title: "Bands", value: "\(asyncStats.uniqueBands)", icon: "waveform")
            }

            // Activations - deferred stat
            if let stats = asyncStats.getStats(), asyncStats.successfulActivations != nil {
                NavigationLink {
                    StatDetailView(
                        category: .parks, items: stats.items(for: .parks), tourState: tourState
                    )
                } label: {
                    ActivationsStatBox(successful: asyncStats.successfulActivations)
                }
                .buttonStyle(.plain)
            } else {
                ActivationsStatBox(successful: asyncStats.successfulActivations)
            }
        }
    }
}

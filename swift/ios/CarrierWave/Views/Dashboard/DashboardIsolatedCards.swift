import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - ActivityCardContent

/// Isolated view for the activity grid card.
/// Reads `activationActivityByDate` and `activityLogActivityByDate` in its own
/// body so changes to these properties do NOT re-evaluate DashboardView.body
/// (which would re-create all dashboard cards including the expensive ActivityGrid).
struct ActivityCardContent: View {
    // MARK: Internal

    let asyncStats: AsyncQSOStatistics

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Activity")
                    .font(.headline)
                Spacer()
                StatsQSOCountLabel(asyncStats: asyncStats)
            }

            ActivityGrid(
                activationData: asyncStats.activationActivityByDate,
                activityLogData: asyncStats.activityLogActivityByDate,
                amtData: amt.isSignedIn ? amt.activityByUTCDay : nil
            )

            StatsProgressIndicator(asyncStats: asyncStats)
        }
        .padding(.vertical, 4)
    }

    // MARK: Private

    /// Another Morse Trainer practice days overlay the QSO grid in purple
    /// once the user has connected AMT (Settings › Services).
    private var amt: AMTService {
        AMTService.shared
    }
}

// MARK: - StatsSummaryGrid

/// Isolated view for the stats grid.
/// Reads stat counts (`totalQSOs`, `confirmedQSLs`, etc.) in its own body
/// so changes only re-evaluate this grid, not the entire DashboardView.
struct StatsSummaryGrid: View {
    // MARK: Internal

    let asyncStats: AsyncQSOStatistics
    let columns: [GridItem]
    let lotwIsConfigured: Bool
    let tourState: TourState
    let onQSOsTapped: () -> Void

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            qsosBox
            qslsBox
            dxccBox
            gridsBox
            bandsBox
            activationsBox
        }
        .sheet(item: $infoCategory) { category in
            StatExplanationSheet(
                methodology: category.detailedExplanation,
                filterPipeline: asyncStats.filterPipeline(for: category)
            )
        }
    }

    // MARK: Private

    @State private var infoCategory: StatCategoryType?

    private var qsosBox: some View {
        Button(action: onQSOsTapped) {
            StatBox(
                title: "QSOs",
                value: "\(asyncStats.totalQSOs)",
                icon: "antenna.radiowaves.left.and.right"
            )
        }
        .buttonStyle(.plain)
    }

    private var qslsBox: some View {
        Group {
            if asyncStats.confirmedQSLs != nil {
                NavigationLink {
                    LazyStatDetailView(
                        category: .qsls, asyncStats: asyncStats, tourState: tourState
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
        }
        .statInfoMenu(category: .qsls, onInfo: showInfo)
    }

    private var dxccBox: some View {
        Group {
            if lotwIsConfigured {
                if asyncStats.uniqueEntities != nil {
                    NavigationLink {
                        LazyStatDetailView(
                            category: .entities, asyncStats: asyncStats, tourState: tourState
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
        }
        .statInfoMenu(category: .entities, onInfo: showInfo)
    }

    private var gridsBox: some View {
        NavigationLink {
            LazyStatDetailView(
                category: .grids, asyncStats: asyncStats, tourState: tourState
            )
        } label: {
            StatBox(
                title: "Grids", value: "\(asyncStats.uniqueGrids)", icon: "square.grid.3x3"
            )
        }
        .buttonStyle(.plain)
        .statInfoMenu(category: .grids, onInfo: showInfo)
    }

    private var bandsBox: some View {
        NavigationLink {
            LazyStatDetailView(
                category: .bands, asyncStats: asyncStats, tourState: tourState
            )
        } label: {
            StatBox(
                title: "Bands", value: "\(asyncStats.uniqueBands)", icon: "waveform"
            )
        }
        .buttonStyle(.plain)
        .statInfoMenu(category: .bands, onInfo: showInfo)
    }

    private var activationsBox: some View {
        Group {
            if asyncStats.successfulActivations != nil {
                NavigationLink {
                    LazyStatDetailView(
                        category: .parks, asyncStats: asyncStats, tourState: tourState
                    )
                } label: {
                    ActivationsStatBox(successful: asyncStats.successfulActivations)
                }
                .buttonStyle(.plain)
            } else {
                ActivationsStatBox(successful: asyncStats.successfulActivations)
            }
        }
        .statInfoMenu(category: .parks, onInfo: showInfo)
    }

    private func showInfo(for category: StatCategoryType) {
        infoCategory = category
    }
}

// MARK: - Stat Context Menu

private extension View {
    func statInfoMenu(
        category: StatCategoryType,
        onInfo: @escaping (StatCategoryType) -> Void
    ) -> some View {
        contextMenu {
            Button {
                onInfo(category)
            } label: {
                Label("What's This?", systemImage: "info.circle")
            }
        }
    }
}

// MARK: - FavoritesCardWrapper

/// Isolated view that gates FavoritesCard on `asyncStats.hasComputed`.
/// Prevents DashboardView.body from observing `hasComputed`.
struct FavoritesCardWrapper: View {
    let asyncStats: AsyncQSOStatistics
    let tourState: TourState

    var body: some View {
        if asyncStats.hasComputed {
            FavoritesCard(asyncStats: asyncStats, tourState: tourState)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Favorites")
                    .font(.headline)
                Text("Loading...")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - WASCardWrapper

/// Isolated view that gates WASCard on `asyncStats.wasData`.
/// Prevents DashboardView.body from observing `wasData` or `wasAvailableModes`.
struct WASCardWrapper: View {
    let asyncStats: AsyncQSOStatistics

    var body: some View {
        if !asyncStats.wasData.isEmpty {
            WASCard(
                wasData: asyncStats.wasData,
                availableModes: asyncStats.wasAvailableModes
            )
        }
    }
}

// MARK: - LazyStatDetailView

/// Wrapper that lazily loads QSOStatistics when the view appears.
/// Computes on a background actor to avoid blocking the main thread.
struct LazyStatDetailView: View {
    // MARK: Internal

    let category: StatCategoryType
    let asyncStats: AsyncQSOStatistics
    let tourState: TourState

    var body: some View {
        Group {
            if let items {
                StatDetailView(category: category, items: items, tourState: tourState)
            } else {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            if let stats = asyncStats.getStats() {
                items = stats.items(for: category)
            } else {
                // Yield first so the loading UI renders before the fetch blocks
                await Task.yield()
                let descriptor = BoundedDescriptor<QSO>(
                    predicate: #Predicate { !$0.isHidden },
                    sortBy: [SortDescriptor(\.timestamp, order: .reverse)],
                    limit: BoundedDescriptor<QSO>.maxLimit
                )
                if let qsos = try? modelContext.boundedFetch(descriptor) {
                    let stats = QSOStatistics(qsos: qsos)
                    items = stats.items(for: category)
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext
    @State private var items: [StatCategoryItem]?
}

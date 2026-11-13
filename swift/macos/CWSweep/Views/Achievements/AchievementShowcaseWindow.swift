import CarrierWaveData
import SwiftUI

// MARK: - AchievementShowcaseWindow

/// Top-level window that shows the catalog and the operator's earned
/// badges. Read-only — Sweep doesn't yet have an auth token, so awarding
/// the `sweep-user` signal is a follow-up.
struct AchievementShowcaseWindow: View {
    // MARK: Internal

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 480, minHeight: 480)
        .task(id: callsign) {
            await load()
        }
    }

    // MARK: Private

    // MARK: - LoadState

    private enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @State private var catalog: [Achievement] = []
    @State private var earnedIDs: Set<String> = []
    @State private var loadState: LoadState = .idle
    @State private var selected: Achievement?
    @AppStorage("loggerDefaultCallsign") private var callsign: String = ""

    private var grouped: [(Achievement.Category, [Achievement])] {
        let visible = catalog.filter { !$0.secret || earnedIDs.contains($0.id) }
        let buckets = Dictionary(grouping: visible, by: \.category)
        return Achievement.Category.allCases.compactMap { category in
            guard let items = buckets[category]?.sorted(by: { $0.sortOrder < $1.sortOrder }),
                  !items.isEmpty
            else {
                return nil
            }
            return (category, items)
        }
    }

    private var header: some View {
        HStack {
            Text("Badges")
                .font(.title2.weight(.semibold))
            Spacer()
            if !callsign.isEmpty {
                Text(callsign.uppercased())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Button {
                Task { await load() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
        }
        .padding()
    }

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .idle,
             .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            grid
        case let .failed(message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                Text("Couldn't load badges").font(.headline)
                Text(message).font(.caption).foregroundStyle(.secondary)
                Button("Retry") { Task { await load() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(grouped, id: \.0) { category, items in
                    section(title: title(for: category), items: items)
                }
            }
            .padding()
        }
    }

    private func section(title: String, items: [Achievement]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 12) {
                ForEach(items) { item in
                    Button {
                        selected = item
                    } label: {
                        AchievementBadgeView(
                            achievement: item,
                            earned: earnedIDs.contains(item.id)
                        )
                    }
                    .buttonStyle(.plain)
                    .popover(
                        isPresented: Binding(
                            get: { selected == item },
                            set: { isPresented in
                                if !isPresented, selected == item {
                                    selected = nil
                                }
                            }
                        ),
                        arrowEdge: .top
                    ) {
                        AchievementDetailPopover(
                            achievement: item,
                            earned: earnedIDs.contains(item.id)
                        )
                    }
                }
            }
        }
    }

    private func title(for category: Achievement.Category) -> String {
        switch category {
        case .creator: "Creators"
        case .community: "Community"
        case .activity: "On the Air"
        case .ecosystem: "Ecosystem"
        case .streak: "Streaks"
        case .quirky: "Curiosities"
        case .unknown: "Other"
        }
    }

    private func load() async {
        loadState = .loading
        do {
            async let catalogFetch = AchievementsFetcher.fetchCatalog()
            async let awardsFetch = AchievementsFetcher.fetchAwards(for: callsign)
            let (cat, awards) = try await (catalogFetch, awardsFetch)
            catalog = cat
            earnedIDs = Set(awards.map(\.achievementId))
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }
}

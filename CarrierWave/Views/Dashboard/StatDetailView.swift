import CarrierWaveData
import SwiftUI

struct StatDetailView: View {
    // MARK: Internal

    let category: StatCategoryType
    let items: [StatCategoryItem]
    let tourState: TourState

    var body: some View {
        List {
            ForEach(cachedSortedItems) { item in
                StatItemRow(item: item)
            }
        }
        .listStyle(.plain)
        .navigationTitle(category.title)
        .miniTour(.statsDrilldown, tourState: tourState)
        .task {
            updateSortedItems()
        }
        .onChange(of: sortMode) { _, _ in
            updateSortedItems()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if category == .parks {
                        Button {
                            sortMode = .date
                        } label: {
                            HStack {
                                Text("By Date")
                                if sortMode == .date {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }

                    Button {
                        sortMode = .count
                    } label: {
                        HStack {
                            Text("By Count")
                            if sortMode == .count {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    Button {
                        sortMode = .alphabetical
                    } label: {
                        HStack {
                            Text("A-Z")
                            if sortMode == .alphabetical {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
        }
    }

    // MARK: Private

    private enum SortMode {
        case date
        case count
        case alphabetical
    }

    @State private var sortMode: SortMode = .date
    @State private var cachedSortedItems: [StatCategoryItem] = []

    private func updateSortedItems() {
        switch sortMode {
        case .date:
            // Sort by date descending; fall back to count if no date
            cachedSortedItems = items.sorted { lhs, rhs in
                if let lhsDate = lhs.date, let rhsDate = rhs.date {
                    return lhsDate > rhsDate
                }
                return lhs.count > rhs.count
            }
        case .count:
            cachedSortedItems = items.sorted { $0.count > $1.count }
        case .alphabetical:
            cachedSortedItems = items.sorted {
                $0.identifier.localizedCaseInsensitiveCompare($1.identifier) == .orderedAscending
            }
        }
    }
}

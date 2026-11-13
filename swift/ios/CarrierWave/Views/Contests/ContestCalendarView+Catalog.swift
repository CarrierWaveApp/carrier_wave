import CarrierWaveData
import SwiftUI

// MARK: - ContestCalendarView+Catalog

extension ContestCalendarView {
    /// Load a definition (using cache when possible) and hand it to the picker
    /// callback. Called from `catalogRow`'s row Button in picker mode.
    func selectInPicker(entry: ContestBrowserEntry) {
        if let definition = entry.definition {
            onSelectDefinition?(definition)
            return
        }
        Task { @MainActor in
            pickerLoadingID = entry.id
            let definition = await refresher.definition(id: entry.id)
            pickerLoadingID = nil
            if let definition {
                onSelectDefinition?(definition)
            } else {
                loadErrorMessage = refresher.lastError
                showLoadError = true
            }
        }
    }

    var sortedEntries: [ContestBrowserEntry] {
        let definitionsByID = Dictionary(
            uniqueKeysWithValues: refresher.definitions.map { ($0.id, $0) }
        )
        let entries: [ContestBrowserEntry] = refresher.summaries.map { summary in
            ContestBrowserEntry(summary: summary, definition: definitionsByID[summary.id])
        }
        return entries.sorted { lhs, rhs in
            switch (lhs.nextStart, rhs.nextStart) {
            case let (left?, right?): left < right
            case (nil, _?): false
            case (_?, nil): true
            default: lhs.displayName < rhs.displayName
            }
        }
    }

    var filteredEntries: [ContestBrowserEntry] {
        guard !searchText.isEmpty else {
            return sortedEntries
        }
        let query = searchText.lowercased()
        return sortedEntries.filter {
            $0.displayName.lowercased().contains(query)
                || $0.name.lowercased().contains(query)
                || $0.id.lowercased().contains(query)
        }
    }

    var liveEntries: [ContestBrowserEntry]? {
        let live = filteredEntries.filter(\.isLive)
        return live.isEmpty ? nil : live
    }

    @ViewBuilder
    var catalogList: some View {
        if refresher.summaries.isEmpty, refresher.definitions.isEmpty {
            ContentUnavailableView {
                Label("No Contests", systemImage: "trophy")
            } description: {
                Text(refresher.lastError ?? "Couldn't load contest definitions.")
            } actions: {
                Button("Retry") { Task { await refresher.refresh() } }
            }
        } else {
            List {
                Section {
                    EmptyView()
                } footer: {
                    Text(
                        "Contests with full scoring, exchange, and Cabrillo support. "
                            + "The calendar also includes contests from the WA7BNM feed."
                    )
                }
                if let live = liveEntries, !live.isEmpty {
                    Section("Live now") {
                        ForEach(live) { entry in catalogRow(entry) }
                    }
                }
                Section("\(filteredEntries.count) supported contests") {
                    ForEach(filteredEntries) { entry in catalogRow(entry) }
                }
                if let last = refresher.lastRefreshed {
                    Section {
                        EmptyView()
                    } footer: {
                        Text("Updated \(last.formatted(.relative(presentation: .named)))")
                    }
                }
            }
        }
    }

    @ViewBuilder
    func catalogRow(_ entry: ContestBrowserEntry) -> some View {
        if isPickerMode {
            Button {
                selectInPicker(entry: entry)
            } label: {
                ContestBrowserRow(
                    entry: entry,
                    isLoading: pickerLoadingID == entry.id
                )
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                ContestDetailView(entry: entry, refresher: refresher)
            } label: {
                ContestBrowserRow(entry: entry)
            }
        }
    }
}

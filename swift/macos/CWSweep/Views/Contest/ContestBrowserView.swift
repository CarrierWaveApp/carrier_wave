import CarrierWaveData
import SwiftUI

// MARK: - ContestBrowserView

/// Full catalog of server-published contest definitions with list and
/// calendar views. List view uses NavigationSplitView for master-detail.
struct ContestBrowserView: View {
    // MARK: Internal

    var body: some View {
        Group {
            if isLoading, entries.isEmpty {
                ProgressView("Loading contests...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty, !isLoading {
                emptyState
            } else {
                content
            }
        }
        .toolbar {
            ToolbarItem {
                Picker("View", selection: $viewMode) {
                    Image(systemName: "list.bullet").tag(ViewMode.list)
                    Image(systemName: "calendar").tag(ViewMode.calendar)
                }
                .pickerStyle(.segmented)
                .frame(width: 80)
            }
            ToolbarItem {
                Button {
                    Task { await refresher.refresh(); rebuildEntries() }
                } label: {
                    if refresher.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(refresher.isRefreshing)
                .help("Refresh contest catalog")
            }
        }
        .searchable(text: $searchText, prompt: "Search contests")
        .task {
            isLoading = true
            await refresher.refreshIfStale()
            rebuildEntries()
            isLoading = false
            if let error = refresher.lastError {
                print("[ContestBrowser] refresh error: \(error)")
            }
            print("[ContestBrowser] loaded \(entries.count) entries from \(refresher.summaries.count) summaries")
        }
    }

    // MARK: Private

    private enum ViewMode: String {
        case list
        case calendar
    }

    @State private var refresher = ContestDefinitionsRefresher()
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var selectedEntryID: String?
    @State private var entries: [ContestBrowserEntry] = []
    @State private var viewMode: ViewMode = .list

    private var filtered: [ContestBrowserEntry] {
        guard !searchText.isEmpty else {
            return entries
        }
        let query = searchText.lowercased()
        return entries.filter {
            $0.displayName.lowercased().contains(query)
                || $0.name.lowercased().contains(query)
                || $0.id.lowercased().contains(query)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Contests", systemImage: "trophy")
        } description: {
            Text(refresher.lastError ?? "Couldn't load contest definitions from the server.")
        } actions: {
            Button("Retry") {
                Task { await refresher.refresh(); rebuildEntries() }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewMode {
        case .list:
            contestList
        case .calendar:
            calendarView
        }
    }

    // MARK: - List View

    private var contestList: some View {
        HStack(spacing: 0) {
            contestSidebar
                .frame(width: 260)

            Divider()

            detailPane
        }
    }

    private var contestSidebar: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                let live = filtered.filter(\.isLive)
                if !live.isEmpty {
                    sidebarSectionHeader("Live Now")
                    ForEach(live) { entry in
                        contestRow(entry)
                    }
                }
                sidebarSectionHeader("All Contests")
                ForEach(filtered) { entry in
                    contestRow(entry)
                }
                if let last = refresher.lastRefreshed {
                    Text("Updated \(last.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                }
            }
        }
        .background(.background)
    }

    // MARK: - Calendar View

    private var calendarView: some View {
        HSplitView {
            ContestCalendarView(entries: entries) { entryID in
                selectedEntryID = entryID
            }
            .frame(minWidth: 400, idealWidth: 500)

            detailPane
                .frame(minWidth: 300)
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let selectedEntryID,
           let entry = entries.first(where: { $0.id == selectedEntryID })
        {
            ContestDetailMacView(entry: entry, refresher: refresher)
        } else {
            Text("Select a contest")
                .font(.title3)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func sidebarSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    private func contestRow(_ entry: ContestBrowserEntry) -> some View {
        Button {
            selectedEntryID = entry.id
        } label: {
            ContestBrowserRowMac(entry: entry)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .background(
                    selectedEntryID == entry.id
                        ? Color.accentColor.opacity(0.2)
                        : Color.clear
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data

    private func rebuildEntries() {
        let definitionsByID = Dictionary(
            uniqueKeysWithValues: refresher.definitions.map { ($0.id, $0) }
        )
        let built: [ContestBrowserEntry] = refresher.summaries.map { summary in
            ContestBrowserEntry(summary: summary, definition: definitionsByID[summary.id])
        }
        entries = built.sorted { lhs, rhs in
            switch (lhs.nextStart, rhs.nextStart) {
            case let (left?, right?): left < right
            case (nil, _?): false
            case (_?, nil): true
            default: lhs.displayName < rhs.displayName
            }
        }
    }
}

// MARK: - ContestBrowserEntry

struct ContestBrowserEntry: Identifiable, Equatable {
    // MARK: Lifecycle

    init(summary: ContestDefinitionSummary, definition: ContestDefinition?) {
        id = summary.id
        name = summary.name
        displayName = summary.displayName
        sponsorName = summary.sponsorName
        isActive = summary.isActive
        self.definition = definition
        if let definition {
            let active = ContestScheduleEvaluator.activeOccurrence(schedule: definition.schedule)
            let next = ContestScheduleEvaluator.nextOccurrence(schedule: definition.schedule)
            occurrence = active ?? next
            isLive = active != nil
        } else {
            occurrence = nil
            isLive = false
        }
    }

    // MARK: Internal

    let id: String
    let name: String
    let displayName: String
    let sponsorName: String?
    let isActive: Bool
    let definition: ContestDefinition?
    let occurrence: ContestOccurrence?
    let isLive: Bool

    var nextStart: Date? {
        occurrence?.start
    }
}

// MARK: - ContestBrowserRowMac

struct ContestBrowserRowMac: View {
    let entry: ContestBrowserEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(entry.displayName)
                    .font(.body.weight(.medium))
                if entry.isLive {
                    Text("LIVE")
                        .font(.caption2.weight(.heavy))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.green.opacity(0.2), in: Capsule())
                        .foregroundStyle(.green)
                }
            }
            if let sponsor = entry.sponsorName {
                Text(sponsor)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let occurrence = entry.occurrence {
                ContestScheduleCaptionMac(occurrence: occurrence, isLive: entry.isLive)
            }
            if let definition = entry.definition {
                HStack(spacing: 4) {
                    ContestModeChips(modes: definition.modes)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - ContestScheduleCaptionMac

/// Renders a pre-computed occurrence as a caption. Does NOT call
/// `ContestScheduleEvaluator` — the entry pre-computes that once.
struct ContestScheduleCaptionMac: View {
    // MARK: Internal

    let occurrence: ContestOccurrence
    let isLive: Bool

    var body: some View {
        Label(captionText, systemImage: isLive ? "dot.radiowaves.left.and.right" : "calendar")
            .font(.caption)
            .foregroundStyle(isLive ? .green : .secondary)
    }

    // MARK: Private

    private var captionText: String {
        if isLive {
            let remaining = occurrence.end.timeIntervalSince(Date())
            let hours = Int(remaining) / 3_600
            let minutes = (Int(remaining) % 3_600) / 60
            return hours > 0
                ? "Live — ends in \(hours)h \(minutes)m"
                : "Live — ends in \(minutes)m"
        }
        return "Next \(occurrence.start.formatted(.relative(presentation: .named)))"
    }
}

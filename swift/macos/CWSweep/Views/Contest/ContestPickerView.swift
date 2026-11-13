import CarrierWaveData
import SwiftUI

// MARK: - ContestPickerView

/// Sheet for selecting a contest from the server-published catalog.
/// Used from the contester layout to pick the active contest definition.
struct ContestPickerView: View {
    // MARK: Internal

    @Binding var selectedContest: ContestDefinition?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            Group {
                if isLoading, entries.isEmpty {
                    ProgressView("Loading contests...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if entries.isEmpty, !isLoading {
                    emptyState
                } else {
                    summaryList
                }
            }
        }
        .frame(width: 450, height: 500)
        .task {
            isLoading = true
            await refresher.refreshIfStale()
            rebuildEntries()
            isLoading = false
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var refresher = ContestDefinitionsRefresher()
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var loadingID: String?
    @State private var entries: [ContestPickerEntry] = []

    private var filtered: [ContestPickerEntry] {
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

    private var toolbar: some View {
        HStack {
            Text("Select Contest")
                .font(.headline)
            Spacer()
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
            .buttonStyle(.borderless)
            .disabled(refresher.isRefreshing)
            Button("Cancel") { dismiss() }
                .buttonStyle(.bordered)
        }
        .padding()
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

    private var summaryList: some View {
        VStack(spacing: 0) {
            TextField("Search contests", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.vertical, 8)

            List {
                ForEach(filtered) { entry in
                    Button {
                        Task { await select(entry: entry) }
                    } label: {
                        HStack {
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
                            }
                            Spacer()
                            if loadingID == entry.id {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if let last = refresher.lastRefreshed {
                HStack {
                    Spacer()
                    Text("Updated \(last.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
    }

    private func rebuildEntries() {
        let definitionsByID = Dictionary(
            uniqueKeysWithValues: refresher.definitions.map { ($0.id, $0) }
        )
        if refresher.summaries.isEmpty {
            entries = refresher.definitions.map { ContestPickerEntry(definition: $0) }
        } else {
            entries = refresher.summaries.map { summary in
                ContestPickerEntry(summary: summary, definition: definitionsByID[summary.id])
            }
        }
    }

    private func select(entry: ContestPickerEntry) async {
        if let cached = entry.definition {
            selectedContest = cached
            dismiss()
            return
        }
        loadingID = entry.id
        let definition = await refresher.definition(id: entry.id)
        loadingID = nil
        if let definition {
            selectedContest = definition
            dismiss()
        }
    }
}

// MARK: - ContestPickerEntry

private struct ContestPickerEntry: Identifiable {
    // MARK: Lifecycle

    init(definition: ContestDefinition) {
        id = definition.id
        name = definition.name
        displayName = definition.displayName
        sponsorName = definition.sponsor?.name
        self.definition = definition
        let active = ContestScheduleEvaluator.activeOccurrence(schedule: definition.schedule)
        let next = ContestScheduleEvaluator.nextOccurrence(schedule: definition.schedule)
        occurrence = active ?? next
        isLive = active != nil
    }

    init(summary: ContestDefinitionSummary, definition: ContestDefinition?) {
        id = summary.id
        name = summary.name
        displayName = summary.displayName
        sponsorName = summary.sponsorName
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
    let definition: ContestDefinition?
    let occurrence: ContestOccurrence?
    let isLive: Bool
}

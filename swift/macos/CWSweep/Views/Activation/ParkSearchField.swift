import CarrierWaveData
import Foundation
import SwiftData
import SwiftUI

// MARK: - RecentPark

private struct RecentPark: Codable, Equatable {
    let reference: String
    let name: String
}

// MARK: - ParkCommunityStats

/// Community stats fetched from activities.carrierwave.app for a single park.
private struct ParkCommunityStats: Codable {
    let totalActivations: Int
    let totalQsos: Int
}

// MARK: - ParkSearchField

/// macOS park search text field with typeahead from locally cached POTA parks.
/// Shows recent parks when focused with no query, and local search results while typing.
/// Fetches community stats from activities.carrierwave.app for each result.
struct ParkSearchField: View {
    // MARK: Internal

    @Binding var selectedReference: String

    var onParkSelected: (_ reference: String, _ name: String, _ grid: String?) -> Void

    var body: some View {
        fieldRow
            .captureFrameInGlobal(into: $fieldFrame)
            .overlay(alignment: .topLeading) {
                if showSuggestions {
                    suggestionsOverlay
                        .offset(y: 34)
                        .captureFrameInGlobal(into: $overlayFrame)
                }
            }
            .zIndex(showSuggestions ? 100 : 0)
            .dismissOnOutsideInteraction(
                isOpen: showSuggestions,
                fieldFrame: fieldFrame,
                overlayFrame: overlayFrame,
                onDismiss: { isFieldFocused = false }
            )
    }

    // MARK: Private

    @AppStorage("recentPOTAParks") private var recentParksData = ""
    @State private var queryText = ""
    @State private var suggestions: [POTAParkEntry] = []
    @State private var communityStats: [String: ParkCommunityStats] = [:]
    @State private var localStats: [String: ReferenceStats] = [:]
    @FocusState private var isFieldFocused: Bool
    @State private var searchTask: Task<Void, Never>?
    @State private var fieldFrame: CGRect = .zero
    @State private var overlayFrame: CGRect = .zero
    @Environment(\.modelContext) private var modelContext

    private var recentParks: [RecentPark] {
        guard !recentParksData.isEmpty,
              let data = recentParksData.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([RecentPark].self, from: data)
        else {
            return []
        }
        return decoded
    }

    private var showSuggestions: Bool {
        guard isFieldFocused, selectedReference.isEmpty else {
            return false
        }
        if queryText.isEmpty {
            return !recentParks.isEmpty
        }
        return !suggestions.isEmpty
    }
}

// MARK: - Subviews

private extension ParkSearchField {
    var fieldRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "tree")
                .foregroundStyle(.secondary)
                .imageScale(.small)

            if selectedReference.isEmpty {
                TextField("Park reference or name (e.g. US-1234)", text: $queryText)
                    .textFieldStyle(.plain)
                    .focused($isFieldFocused)
                    .onSubmit { confirmTopSuggestion() }
                    .onChange(of: queryText) { scheduleSearch() }
                    .onKeyPress(.escape) {
                        isFieldFocused = false
                        return .handled
                    }
            } else {
                selectedParkLabel
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    isFieldFocused ? Color.accentColor : Color.secondary.opacity(0.3),
                    lineWidth: 1
                )
        )
    }

    var selectedParkLabel: some View {
        HStack {
            Text(selectedReference)
                .font(.body)
            Spacer()
            Button {
                clearSelection()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Clear park selection")
        }
    }

    var suggestionsOverlay: some View {
        VStack(spacing: 0) {
            if queryText.isEmpty {
                recentSection
            } else {
                resultsSection
            }
        }
        .frame(width: 520)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.14))
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 6)
    }

    var recentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent Parks")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, 3)

            ForEach(recentParks.prefix(6), id: \.reference) { park in
                recentParkRow(park)
            }
        }
        .task(id: "recentStats") {
            let refs = recentParks.prefix(6).map(\.reference)
            await fetchCommunityStatsForRefs(refs)
        }
    }

    var resultsSection: some View {
        VStack(spacing: 0) {
            ForEach(suggestions.prefix(10), id: \.reference) { park in
                parkResultRow(park)
                if park.reference != suggestions.last?.reference {
                    Divider().padding(.horizontal, 10)
                }
            }
        }
    }
}

// MARK: - Row Views

private extension ParkSearchField {
    func recentParkRow(_ park: RecentPark) -> some View {
        Button {
            selectPark(reference: park.reference, name: park.name, grid: nil)
        } label: {
            HStack {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
                    .imageScale(.small)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(park.reference)
                        .font(.body.monospaced().weight(.semibold))
                        .foregroundStyle(.green)
                    Text(park.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    statsRow(for: park.reference)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight()
    }

    func parkResultRow(_ park: POTAParkEntry) -> some View {
        Button {
            selectPark(reference: park.reference, name: park.name, grid: park.grid)
        } label: {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(park.reference)
                            .font(.body.monospaced().weight(.semibold))
                            .foregroundStyle(.green)
                        if !park.locationDesc.isEmpty {
                            Text(park.locationDesc)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(park.name)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    statsRow(for: park.reference)
                }

                Spacer()

                if let grid = park.grid {
                    Text(grid)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight()
    }

    @ViewBuilder
    func statsRow(for reference: String) -> some View {
        let community = communityStats[reference]
        let local = localStats[reference]
        let hasStats = community != nil || (local != nil && local!.qsoCount > 0)

        if hasStats {
            HStack(spacing: 8) {
                if let community {
                    communityBadge(community)
                }
                if let local, local.qsoCount > 0 {
                    myStatsBadge(local)
                }
            }
        }
    }

    func communityBadge(_ stats: ParkCommunityStats) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "person.3.fill")
                .font(.caption2)
            Text("\(stats.totalActivations) act")
                .font(.caption.monospacedDigit())
            Text("·")
                .font(.caption)
            Text("\(stats.totalQsos) Qs")
                .font(.caption.monospacedDigit())
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.orange.opacity(0.1))
        .clipShape(Capsule())
    }

    func myStatsBadge(_ stats: ReferenceStats) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.caption2)
            Text("\(stats.activationCount)")
                .font(.caption.monospacedDigit())
            Text("·")
                .font(.caption)
            Text("\(stats.qsoCount) Qs")
                .font(.caption.monospacedDigit())
        }
        .foregroundStyle(.blue)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.blue.opacity(0.1))
        .clipShape(Capsule())
    }
}

// MARK: - Actions

private extension ParkSearchField {
    func scheduleSearch() {
        searchTask?.cancel()
        let query = queryText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            suggestions = []
            return
        }

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else {
                return
            }
            let results = POTAParksCache.shared.search(query, limit: 20)
            guard !Task.isCancelled else {
                return
            }
            suggestions = results

            // Load local stats
            await loadLocalStats(for: results)

            // Fetch community stats for visible results
            await fetchCommunityStats(for: results)
        }
    }

    func confirmTopSuggestion() {
        if queryText.isEmpty, let first = recentParks.first {
            selectPark(reference: first.reference, name: first.name, grid: nil)
        } else if let first = suggestions.first {
            selectPark(
                reference: first.reference,
                name: first.name,
                grid: first.grid
            )
        }
    }

    func selectPark(reference: String, name: String, grid: String?) {
        selectedReference = reference
        queryText = ""
        suggestions = []
        isFieldFocused = false
        saveRecent(reference: reference, name: name)
        onParkSelected(reference, name, grid)
    }

    func clearSelection() {
        selectedReference = ""
        queryText = ""
        suggestions = []
    }

    func saveRecent(reference: String, name: String) {
        var recents = recentParks
        recents.removeAll { $0.reference == reference }
        recents.insert(RecentPark(reference: reference, name: name), at: 0)
        recents = Array(recents.prefix(10))
        if let data = try? JSONEncoder().encode(recents),
           let str = String(data: data, encoding: .utf8)
        {
            recentParksData = str
        }
    }
}

// MARK: - Stats Loading

private extension ParkSearchField {
    func loadLocalStats(for parks: [POTAParkEntry]) async {
        let loader = ReferenceStatsLoader()
        let allStats = await loader.loadStats(
            container: modelContext.container,
            field: .parkReference
        )
        // Only keep stats for parks in the current result set
        let refs = Set(parks.map(\.reference))
        var filtered: [String: ReferenceStats] = [:]
        for (key, value) in allStats where refs.contains(key) {
            filtered[key] = value
        }
        localStats = filtered
    }

    func fetchCommunityStats(for parks: [POTAParkEntry]) async {
        let refs = parks.prefix(10).map(\.reference)
        await fetchCommunityStatsForRefs(refs)
    }

    func fetchCommunityStatsForRefs(_ refs: [String]) async {
        await withTaskGroup(of: (String, ParkCommunityStats?).self) { group in
            for ref in refs where communityStats[ref] == nil {
                group.addTask {
                    let stats = await Self.fetchParkStats(reference: ref)
                    return (ref, stats)
                }
            }
            for await (ref, stats) in group {
                if let stats {
                    communityStats[ref] = stats
                }
            }
        }
    }

    static func fetchParkStats(reference: String) async -> ParkCommunityStats? {
        let encoded = reference.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? reference
        let urlString = "https://activities.carrierwave.app/v1/pota/stats/park/\(encoded)"
        guard let url = URL(string: urlString) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("CWSweep/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200 ... 299).contains(http.statusCode)
        else {
            return nil
        }

        struct APIWrapper: Codable {
            struct ParkData: Codable {
                let totalActivations: Int
                let totalQsos: Int
            }

            let data: ParkData
        }

        guard let wrapper = try? JSONDecoder().decode(APIWrapper.self, from: data) else {
            return nil
        }
        return ParkCommunityStats(
            totalActivations: wrapper.data.totalActivations,
            totalQsos: wrapper.data.totalQsos
        )
    }
}

// MARK: - HoverHighlightModifier

private struct HoverHighlightModifier: ViewModifier {
    // MARK: Internal

    func body(content: Content) -> some View {
        content
            .background(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
            .onHover { isHovered = $0 }
    }

    // MARK: Private

    @State private var isHovered = false
}

private extension View {
    func hoverHighlight() -> some View {
        modifier(HoverHighlightModifier())
    }
}

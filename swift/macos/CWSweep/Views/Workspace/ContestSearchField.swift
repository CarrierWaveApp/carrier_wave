import CarrierWaveData
import SwiftUI

// MARK: - ContestSearchField

/// Inline contest typeahead, mirroring the shape of `ParkSearchField`. Pulls
/// the full catalog from `ContestDefinitionsRefresher` and ranks entries so
/// **live-now** contests bubble to the top — operators almost always want to
/// jump into whatever's running right this minute.
///
/// Replaces the modal `ContestPickerView` sheet inside the new session
/// composer flow. The sheet still exists for legacy callers (the contester
/// layout's "Switch contest" button); both can coexist.
struct ContestSearchField: View {
    // MARK: Internal

    @Binding var selectedContest: ContestDefinition?

    var body: some View {
        fieldRow
            .captureFrameInGlobal(into: $fieldFrame)
            .overlay(alignment: .topLeading) {
                if showSuggestions {
                    suggestionsOverlay
                        .offset(y: 38)
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
            .task { await initialLoad() }
    }

    // MARK: Private

    @State private var refresher = ContestDefinitionsRefresher()
    @State private var queryText: String = ""
    @State private var entries: [ContestEntry] = []
    @State private var fieldFrame: CGRect = .zero
    @State private var overlayFrame: CGRect = .zero
    @FocusState private var isFieldFocused: Bool

    private var showSuggestions: Bool {
        guard isFieldFocused, selectedContest == nil else {
            return false
        }
        return !entries.isEmpty
    }

    private var filtered: [ContestEntry] {
        guard !queryText.isEmpty else {
            return Array(entries.prefix(10))
        }
        let query = queryText.lowercased()
        let matches = entries.filter { entry in
            entry.displayName.lowercased().contains(query)
                || entry.name.lowercased().contains(query)
                || entry.id.lowercased().contains(query)
        }
        return Array(matches.prefix(10))
    }
}

// MARK: - Subviews

private extension ContestSearchField {
    var fieldRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "trophy")
                .foregroundStyle(.secondary)
                .imageScale(.small)

            if let selected = selectedContest {
                selectedContestLabel(selected)
            } else {
                TextField("Contest name or id (e.g. CWT, NAQP-CW)", text: $queryText)
                    .textFieldStyle(.plain)
                    .focused($isFieldFocused)
                    .onSubmit { confirmTop() }
                    .onKeyPress(.escape) {
                        isFieldFocused = false
                        return .handled
                    }
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

    func selectedContestLabel(_ contest: ContestDefinition) -> some View {
        HStack {
            Text(contest.displayName)
                .font(.body.weight(.medium))
            if isLive(contest) {
                LiveBadge()
            }
            Spacer()
            Button {
                selectedContest = nil
                queryText = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Clear contest selection")
        }
    }

    var suggestionsOverlay: some View {
        VStack(alignment: .leading, spacing: 0) {
            if refresher.isRefreshing, entries.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .padding(10)
            } else {
                contestList
            }
            footerBar
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

    var contestList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(filtered) { entry in
                contestRow(entry)
                if entry.id != filtered.last?.id {
                    Divider().opacity(0.4).padding(.horizontal, 10)
                }
            }
        }
    }

    func contestRow(_ entry: ContestEntry) -> some View {
        Button {
            Task { await select(entry: entry) }
        } label: {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(entry.displayName)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        if entry.isLive {
                            LiveBadge()
                        }
                    }
                    if let sponsor = entry.sponsorName {
                        Text(sponsor)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let occurrence = entry.occurrence {
                        occurrenceCaption(occurrence: occurrence, isLive: entry.isLive)
                    }
                }
                Spacer()
                if !entry.modes.isEmpty {
                    Text(entry.modes.joined(separator: " · "))
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

    func occurrenceCaption(occurrence: ContestOccurrence, isLive: Bool) -> some View {
        let fmt = Date.FormatStyle().day().month(.abbreviated).hour().minute()
        let prefix = isLive ? "ends " : "starts "
        let target = isLive ? occurrence.end : occurrence.start
        return Text(prefix + target.formatted(.relative(presentation: .named)))
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            + Text(" · " + target.formatted(fmt))
            .font(.caption2.monospaced())
            .foregroundStyle(.tertiary)
    }

    var footerBar: some View {
        HStack {
            if let last = refresher.lastRefreshed {
                Text("Updated \(last.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text("Loading…")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                Task { await refresher.refresh(); rebuildEntries() }
            } label: {
                if refresher.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
            }
            .buttonStyle(.borderless)
            .disabled(refresher.isRefreshing)
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }
}

// MARK: - Actions

private extension ContestSearchField {
    func initialLoad() async {
        await refresher.refreshIfStale()
        rebuildEntries()
    }

    func rebuildEntries() {
        let definitionsByID = Dictionary(
            uniqueKeysWithValues: refresher.definitions.map { ($0.id, $0) }
        )
        let summariesEmpty = refresher.summaries.isEmpty
        let raw: [ContestEntry] = if summariesEmpty {
            refresher.definitions.map { ContestEntry(definition: $0) }
        } else {
            refresher.summaries.map { summary in
                ContestEntry(summary: summary, definition: definitionsByID[summary.id])
            }
        }
        entries = raw.sorted { lhs, rhs in
            if lhs.isLive != rhs.isLive {
                return lhs.isLive
            }
            if lhs.isUpcomingSoon != rhs.isUpcomingSoon {
                return lhs.isUpcomingSoon
            }
            return lhs.displayName < rhs.displayName
        }
    }

    func confirmTop() {
        guard let first = filtered.first else {
            return
        }
        Task { await select(entry: first) }
    }

    func select(entry: ContestEntry) async {
        if let cached = entry.definition {
            selectedContest = cached
            isFieldFocused = false
            return
        }
        if let live = await refresher.definition(id: entry.id) {
            selectedContest = live
            isFieldFocused = false
        }
    }

    func isLive(_ contest: ContestDefinition) -> Bool {
        ContestScheduleEvaluator.activeOccurrence(schedule: contest.schedule) != nil
    }
}

// MARK: - ContestEntry

private struct ContestEntry: Identifiable {
    // MARK: Lifecycle

    init(definition: ContestDefinition) {
        id = definition.id
        name = definition.name
        displayName = definition.displayName
        sponsorName = definition.sponsor?.name
        self.definition = definition
        modes = Array(definition.modes.prefix(3))
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
        modes = definition.map { Array($0.modes.prefix(3)) } ?? []
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
    let modes: [String]
    let occurrence: ContestOccurrence?
    let isLive: Bool

    /// Within the next 24 hours — used so the operator sees today's contests
    /// even when none are live right now.
    var isUpcomingSoon: Bool {
        guard !isLive, let occurrence else {
            return false
        }
        return occurrence.start.timeIntervalSinceNow < 24 * 60 * 60
            && occurrence.start.timeIntervalSinceNow > 0
    }
}

// MARK: - LiveBadge

private struct LiveBadge: View {
    var body: some View {
        Text("LIVE")
            .font(.system(size: 9, weight: .heavy))
            .tracking(0.6)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.green.opacity(0.2), in: Capsule())
            .foregroundStyle(.green)
    }
}

// MARK: - ContestHoverHighlight

private struct ContestHoverHighlight: ViewModifier {
    // MARK: Internal

    func body(content: Content) -> some View {
        content
            .background(isHovered ? Color.accentColor.opacity(0.12) : Color.clear)
            .onHover { isHovered = $0 }
    }

    // MARK: Private

    @State private var isHovered = false
}

private extension View {
    func hoverHighlight() -> some View {
        modifier(ContestHoverHighlight())
    }
}

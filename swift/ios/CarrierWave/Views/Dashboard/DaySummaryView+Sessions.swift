import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - DaySummaryView + Sessions

extension DaySummaryView {
    @ViewBuilder
    var sessionsSection: some View {
        if let snapshot {
            Section("Sessions") {
                let allCards = orderedSessionCards(snapshot: snapshot)
                ForEach(allCards) { card in
                    cardView(for: card)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowSeparator(.hidden)
                }
            }
        }
    }

    private func orderedSessionCards(snapshot: DaySummarySnapshot) -> [SessionCardData] {
        var all = snapshot.sessions
        if let hunter = snapshot.hunterCard {
            all.append(hunter)
        }
        if let loose = snapshot.looseCard {
            all.append(loose)
        }
        return all.sorted { ($0.slicedQSOs.first?.timestamp ?? .distantPast)
            < ($1.slicedQSOs.first?.timestamp ?? .distantPast)
        }
    }

    @ViewBuilder
    private func cardView(for card: SessionCardData) -> some View {
        switch card.kind {
        case let .session(sessionId):
            // The card itself stays full-width; the NavigationLink is an
            // invisible background overlay so the List doesn't decorate
            // the row with a system disclosure chevron that would push
            // the card's right edge inward.
            SessionDayCard(card: card)
                .background {
                    NavigationLink(value: DaySessionDestination(sessionId: sessionId)) {
                        EmptyView()
                    }
                    .opacity(0)
                }
        case .hunter,
             .loose:
            ExpandableDayCard(
                card: card,
                isExpanded: expandedCardIds.contains(card.id),
                toggle: { toggleExpansion(card.id) }
            )
        }
    }

    private func toggleExpansion(_ cardId: String) {
        withAnimation(.easeInOut(duration: 0.22)) {
            if expandedCardIds.contains(cardId) {
                expandedCardIds.remove(cardId)
            } else {
                expandedCardIds.insert(cardId)
            }
        }
    }
}

// MARK: - DaySessionDestination

struct DaySessionDestination: Hashable {
    let sessionId: UUID
}

// MARK: - DaySessionDestinationView

/// Resolves a session id back to a `LoggingSession` model object and
/// renders the existing `SessionDetailView`. Used as the destination
/// for the `.navigationDestination(for: DaySessionDestination.self)`
/// modifier registered upstream.
struct DaySessionDestinationView: View {
    // MARK: Internal

    let sessionId: UUID

    var body: some View {
        if let session = fetchSession() {
            SessionDetailView(session: session)
        } else {
            ContentUnavailableView(
                "Session unavailable",
                systemImage: "questionmark.folder"
            )
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext

    private func fetchSession() -> LoggingSession? {
        let id = sessionId
        let predicate = #Predicate<LoggingSession> { $0.id == id }
        var descriptor = FetchDescriptor<LoggingSession>(predicate: predicate)
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }
}

// MARK: - SessionDayCard

private struct SessionDayCard: View {
    // MARK: Internal

    let card: SessionCardData

    var body: some View {
        DayCardContent(card: card, accessory: .chevronRight)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint("Opens session detail")
            .accessibilityAddTraits(.isButton)
    }

    // MARK: Private

    private var accessibilityLabel: String {
        var parts = [card.title]
        parts.append("\(card.slicedQSOs.count) QSO\(card.slicedQSOs.count == 1 ? "" : "s")")
        if let range = card.timeRange {
            parts.append(DaySessionTimeFormatter.string(from: range, isLive: card.isLive))
        }
        if card.isLive {
            parts.append("live")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - ExpandableDayCard

private struct ExpandableDayCard: View {
    // MARK: Internal

    let card: SessionCardData
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: toggle) {
                DayCardContent(
                    card: card,
                    accessory: isExpanded ? .chevronUp : .chevronDown
                )
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(isExpanded ? "Collapses QSO list" : "Expands QSO list")
            .accessibilityAddTraits(.isButton)

            if isExpanded {
                Divider()
                VStack(spacing: 0) {
                    ForEach(card.slicedQSOs) { snapshot in
                        QSORow(qso: snapshot.makeBridgedQSO(), serviceConfig: ServiceConfiguration())
                            .padding(.vertical, 4)
                    }
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: Private

    private var accessibilityLabel: String {
        let count = card.slicedQSOs.count
        switch card.kind {
        case .hunter: return "Hunter Log, \(count) casual contact\(count == 1 ? "" : "s")"
        case .loose: return "Loose QSOs, \(count) contact\(count == 1 ? "" : "s")"
        case .session: return card.title
        }
    }
}

// MARK: - DayCardContent

/// Unified card body shared by `SessionDayCard` and `ExpandableDayCard`.
/// Layout: type icon + live dot, title (with trailing time + accessory),
/// metadata line (QSO count + duration), continuation chip if any,
/// band/mode pills.
private struct DayCardContent: View {
    // MARK: Internal

    enum Accessory {
        case chevronRight
        case chevronDown
        case chevronUp

        // MARK: Internal

        var symbol: String {
            switch self {
            case .chevronRight: "chevron.right"
            case .chevronDown: "chevron.down"
            case .chevronUp: "chevron.up"
            }
        }
    }

    let card: SessionCardData
    let accessory: Accessory

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            SessionTypeIconView(icon: card.typeIcon)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 6) {
                titleRow
                metadataRow
                if let badge = card.continuationBadge {
                    continuationChip(for: badge)
                }
                if !card.bandPills.isEmpty || !card.modePills.isEmpty {
                    pillsRow
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .contentShape(Rectangle())
    }

    // MARK: Private

    private var qsoCountText: String {
        let count = card.slicedQSOs.count
        switch card.kind {
        case .hunter: return "\(count) casual contact\(count == 1 ? "" : "s")"
        case .loose: return "\(count) loose QSO\(count == 1 ? "" : "s")"
        case .session: return "\(count) QSO\(count == 1 ? "" : "s")"
        }
    }

    private var timeRangeText: String {
        if let range = card.timeRange {
            return DaySessionTimeFormatter.string(from: range, isLive: card.isLive)
        }
        return "All day"
    }

    private var titleRow: some View {
        HStack(spacing: 6) {
            if card.isLive {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
            }
            Text(card.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 8)
            Image(systemName: accessory.symbol)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var metadataRow: some View {
        HStack(spacing: 6) {
            Text(qsoCountText)
            Text("\u{00B7}")
                .foregroundStyle(.tertiary)
            Text(timeRangeText)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var pillsRow: some View {
        FlowLayout(spacing: 4) {
            ForEach(card.bandPills, id: \.band) { entry in
                CountedPill(label: entry.band, count: entry.count, color: .blue)
            }
            ForEach(card.modePills, id: \.mode) { entry in
                CountedPill(label: entry.mode, count: entry.count, color: .green)
            }
        }
    }

    @ViewBuilder
    private func continuationChip(for badge: ContinuationBadge) -> some View {
        let (symbol, label) = continuationLabel(for: badge)
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.caption2)
            Text(label)
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color(.systemGray5)))
    }

    private func continuationLabel(for badge: ContinuationBadge) -> (String, String) {
        switch badge {
        case .continues: ("arrow.right", "continues")
        case .continued: ("arrow.left", "continued")
        case .both: ("arrow.left.and.right", "spans multiple days")
        }
    }
}

// MARK: - SessionTypeIconView

private struct SessionTypeIconView: View {
    // MARK: Internal

    let icon: SessionTypeIcon

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(colorFor(icon))
            Image(systemName: symbolFor(icon))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
        }
    }

    // MARK: Private

    private func colorFor(_ icon: SessionTypeIcon) -> Color {
        switch icon {
        case .pota: .green
        case .sota: .brown
        case .wwff: .mint
        case .aoa: .indigo
        case .tota: .teal
        case .ft8: .purple
        case .contest: .orange
        case .casual: .gray
        case .hunter: .blue
        case .loose: Color(.systemGray2)
        }
    }

    /// Mirrors `ActivationType.icon` so day-view cards match the rest of
    /// the app (callsign timeline, settings, command row).
    private func symbolFor(_ icon: SessionTypeIcon) -> String {
        switch icon {
        case .pota: "tree"
        case .sota: "mountain.2"
        case .wwff: "leaf.fill"
        case .aoa: "eye"
        case .tota: "square.grid.3x3.fill"
        case .ft8: "waveform"
        case .contest: "trophy"
        case .casual: "radio"
        case .hunter: "scope"
        case .loose: "questionmark"
        }
    }
}

// MARK: - DaySessionTimeFormatter

enum DaySessionTimeFormatter {
    // MARK: Internal

    static func string(from range: ClosedRange<Date>, isLive: Bool) -> String {
        let start = formatter.string(from: range.lowerBound)
        let end = isLive ? "live" : formatter.string(from: range.upperBound)
        return "\(start) – \(end)"
    }

    // MARK: Private

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}

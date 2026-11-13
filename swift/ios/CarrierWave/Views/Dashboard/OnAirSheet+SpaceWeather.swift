// On Air Sheet — Space Weather Section
//
// Shows active DONKI space weather events in the On Air sheet,
// grouped by type (GST/FLR/CME) with expand/collapse.

import CarrierWaveCore
import SwiftUI

// MARK: - SpaceWeatherGroup

/// A group of same-type space weather events, sorted worst-first.
private struct SpaceWeatherGroup: Identifiable {
    let typeName: String
    let typeIcon: String
    let events: [DONKIEvent]

    var id: String {
        typeName
    }

    var worstImpact: RadioImpactLevel {
        events.map(\.radioImpact).max() ?? .none
    }

    var leadEvent: DONKIEvent? {
        events.first
    }
}

// MARK: - Space Weather Section

extension OnAirSheet {
    @ViewBuilder
    var spaceWeatherSection: some View {
        let groups = groupedEvents
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(
                    "Space Weather",
                    icon: "exclamationmark.triangle.fill",
                    color: impactColor(donkiService.worstActiveImpact),
                    badge: impactBadge
                )

                VStack(spacing: 0) {
                    ForEach(groups) { group in
                        SpaceWeatherGroupRow(group: group)
                    }
                }
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var groupedEvents: [SpaceWeatherGroup] {
        let events = donkiService.activeEvents
        guard !events.isEmpty else {
            return []
        }

        var gst: [DONKIEvent] = []
        var flr: [DONKIEvent] = []
        var cme: [DONKIEvent] = []

        for event in events {
            switch event {
            case .geostorm: gst.append(event)
            case .flare: flr.append(event)
            case .cme: cme.append(event)
            }
        }

        var groups: [SpaceWeatherGroup] = []
        if !gst.isEmpty {
            groups.append(SpaceWeatherGroup(
                typeName: "Geomagnetic Storms",
                typeIcon: "bolt.fill",
                events: sortByImpact(gst)
            ))
        }
        if !flr.isEmpty {
            groups.append(SpaceWeatherGroup(
                typeName: "Solar Flares",
                typeIcon: "sun.max.trianglebadge.exclamationmark",
                events: sortByImpact(flr)
            ))
        }
        if !cme.isEmpty {
            groups.append(SpaceWeatherGroup(
                typeName: "Coronal Mass Ejections",
                typeIcon: "wind",
                events: sortByImpact(cme)
            ))
        }

        // Sort groups by worst impact descending
        return groups.sorted { $0.worstImpact > $1.worstImpact }
    }

    private func sortByImpact(
        _ events: [DONKIEvent]
    ) -> [DONKIEvent] {
        events.sorted { $0.radioImpact > $1.radioImpact }
    }

    // MARK: - Private Helpers

    private var impactBadge: String? {
        let impact = donkiService.worstActiveImpact
        guard impact >= .moderate else {
            return nil
        }
        return impact.label
    }

    func impactColor(
        _ impact: RadioImpactLevel
    ) -> Color {
        switch impact {
        case .extreme,
             .severe: .red
        case .moderate: .orange
        case .minor: .yellow
        case .none: .secondary
        }
    }
}

// MARK: - OnAirSheet DONKI Service

extension OnAirSheet {
    var donkiService: DONKIPollingService {
        DONKIPollingService.shared
    }
}

// MARK: - SpaceWeatherGroupRow

/// Collapsed/expandable row for a group of same-type events.
private struct SpaceWeatherGroupRow: View {
    // MARK: Internal

    let group: SpaceWeatherGroup

    var body: some View {
        VStack(spacing: 0) {
            if group.events.count == 1 {
                // Single event — show directly without accordion
                headerRow
            } else {
                // Multiple events — expand/collapse
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                } label: {
                    headerRow
                }
                .buttonStyle(.plain)

                if isExpanded {
                    ForEach(
                        group.events,
                        id: \.eventID
                    ) { event in
                        expandedEventRow(event)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    // MARK: Private

    @State private var isExpanded = false

    private var groupColor: Color {
        let impact = group.worstImpact
        switch impact {
        case .extreme,
             .severe: return .red
        case .moderate: return .orange
        case .minor: return .yellow
        case .none: return .secondary
        }
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            Image(systemName: group.typeIcon)
                .font(.system(size: 14))
                .foregroundStyle(groupColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(group.typeName)
                        .font(.subheadline.weight(.medium))

                    Text(group.worstImpact.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(groupColor)
                        .badgePill(groupColor.opacity(0.12))
                }

                if let lead = group.leadEvent {
                    Text(lead.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if group.events.count > 1 {
                Text("\(group.events.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .badgePill(Color(.systemGray4))

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func expandedEventRow(
        _ event: DONKIEvent
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Color.clear.frame(width: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(event.summary)
                        .font(.caption)
                        .foregroundStyle(.primary)

                    if let note = event.note, !note.isEmpty {
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer()
            }

            if let start = event.startDate,
               let expiry = event.expiryDate
            {
                EventTimelineBar(
                    startDate: start,
                    expiryDate: expiry,
                    accentColor: groupColor
                )
                .padding(.leading, 34)
                .padding(.trailing, 12)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.systemGray5).opacity(0.5))
    }
}

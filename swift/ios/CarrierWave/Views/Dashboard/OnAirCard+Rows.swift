import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - OnAirCard Row Views

extension OnAirCard {
    @ViewBuilder
    func itemRow(_ item: OnAirItem) -> some View {
        switch item {
        case let .dxpedition(dx, isLive):
            dxpeditionRow(dx, isLive: isLive)
        case let .contest(contest, isLive):
            contestRow(contest, isLive: isLive)
        }
    }

    func dxpeditionRow(
        _ dx: Ham365DXpedition,
        isLive: Bool
    ) -> some View {
        HStack(spacing: 8) {
            statusDot(isLive: isLive)

            Text(dx.callsign)
                .font(.caption.weight(.semibold).monospaced())
                .lineLimit(1)

            Text(dx.entity)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            if isLive, let spots = onAirSpots[dx.callsign], !spots.isEmpty {
                let grouped = DXpeditionSpotGrouper.group(spots)
                if let top = grouped.first {
                    Text(top.label)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.green)
                        .badgePill(Color.green.opacity(0.12))
                }
            } else if !isLive {
                Text(dx.dateRange)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(minHeight: 28)
    }

    func contestRow(
        _ contest: Contest,
        isLive: Bool
    ) -> some View {
        HStack(spacing: 8) {
            statusDot(isLive: isLive)

            Text(contest.title)
                .font(.caption.weight(.medium))
                .lineLimit(1)

            Spacer()

            if isLive {
                Text("Ends \(contest.formattedEnd)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text(contest.formattedStart)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(minHeight: 28)
    }

    func statusDot(isLive: Bool) -> some View {
        Circle()
            .fill(isLive ? Color.green : Color(.systemGray4))
            .frame(width: 6, height: 6)
            .accessibilityHidden(true)
    }

    func conditionPill(
        icon: String,
        label: String,
        value: String,
        color: Color
    ) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(color)
                .accessibilityHidden(true)
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .fixedSize()
        .badgePill(color.opacity(0.1), verticalPadding: 3)
    }

    func kIndexColor(_ kVal: Double) -> Color {
        switch kVal {
        case ..<2: .green
        case ..<3: .blue
        case ..<4: .yellow
        case ..<5: .orange
        default: .red
        }
    }

    func ratingColor(_ rating: String) -> Color {
        switch rating {
        case "Excellent",
             "Good": .green
        case "Fair": .yellow
        case "Poor": .orange
        default: .red
        }
    }

    func spotCount(_ dx: Ham365DXpedition) -> Int {
        onAirSpots[dx.callsign]?.count ?? 0
    }
}

import SwiftUI

// MARK: - SpaceWeatherSummaryRow

/// Compact row summarizing the worst active space-weather event.
/// Used inside the Solar widget's small + accessory rectangular variants.
struct SpaceWeatherSummaryRow: View {
    let snapshot: WidgetSpaceWeatherSnapshot

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: snapshot.icon)
                .font(.caption2)
                .foregroundStyle(SpaceWeatherImpact.color(snapshot.worstImpactRaw))
            Text(snapshot.headline)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if snapshot.eventCount > 1 {
                Spacer(minLength: 4)
                Text("\(snapshot.eventCount)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - SpaceWeatherImpact

enum SpaceWeatherImpact {
    static func color(_ rawImpact: Int) -> Color {
        switch rawImpact {
        case 0: .secondary
        case 1: .yellow
        case 2: .orange
        case 3: .red
        default: .purple
        }
    }
}

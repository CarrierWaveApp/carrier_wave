// Space Weather Condition Row
//
// Compact row for the On Air card showing active space weather events.
// Also used as debug surface to verify DONKI API connectivity.

import CarrierWaveCore
import SwiftUI

// MARK: - SpaceWeatherConditionRow

/// Compact space weather row for the On Air Now card.
/// Shows a warning pill when moderate+ events are active,
/// hides entirely when there's nothing significant.
struct SpaceWeatherConditionRow: View {
    // MARK: Internal

    var body: some View {
        let impact = donkiService.worstActiveImpact
        let events = donkiService.activeEvents
        let significant = events.filter { $0.radioImpact >= .moderate }

        if !significant.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(impactColor(impact))

                Text(bannerLabel(impact, count: significant.count))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(impactColor(impact))

                Spacer()

                Text(impact.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color(.systemBackground))
                    .badgePill(impactColor(impact))
            }
        }
    }

    // MARK: Private

    @State private var donkiService = DONKIPollingService.shared

    private func impactColor(
        _ impact: RadioImpactLevel
    ) -> Color {
        switch impact {
        case .extreme,
             .severe: .red
        case .moderate: .orange
        default: .yellow
        }
    }

    private func bannerLabel(
        _ impact: RadioImpactLevel,
        count: Int
    ) -> String {
        let noun = count == 1 ? "event" : "events"
        switch impact {
        case .extreme: return "\(count) \(noun) — HF severely degraded"
        case .severe: return "\(count) \(noun) — HF degraded"
        case .moderate: return "\(count) \(noun) — HF may be affected"
        default: return "\(count) space weather \(noun)"
        }
    }
}

// Space Weather Banner View
//
// Sheet content shown when tapping the space weather chip
// in the session controls bar. Shows all active events.

import CarrierWaveCore
import SwiftUI

// MARK: - SpaceWeatherBannerView

struct SpaceWeatherBannerView: View {
    // MARK: Internal

    var onDismiss: (() -> Void)?

    var body: some View {
        let events = pollingService.activeEvents
        let impact = pollingService.worstActiveImpact
        let significantEvents = events.filter {
            $0.radioImpact >= .moderate
        }

        NavigationStack {
            List {
                impactSection(impact)
                eventsSection(significantEvents)
            }
            .navigationTitle("Space Weather")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if let onDismiss {
                        Button("Done", action: onDismiss)
                    }
                }
            }
        }
    }

    // MARK: Private

    @State private var pollingService = DONKIPollingService.shared

    private func impactSection(
        _ impact: RadioImpactLevel
    ) -> some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(bannerColor(impact))
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(impactLabel(impact))
                        .font(.headline)
                    Text(impactDetail(impact))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .listRowBackground(bannerColor(impact).opacity(0.08))
        }
    }

    private func eventsSection(
        _ events: [DONKIEvent]
    ) -> some View {
        Section("Active Events") {
            ForEach(events.prefix(8), id: \.eventID) { event in
                eventRow(event)
            }
        }
    }

    private func eventRow(_ event: DONKIEvent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: event.typeIcon)
                    .font(.system(size: 16))
                    .foregroundStyle(impactColor(event.radioImpact))
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(event.typeName)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(event.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let note = event.note, !note.isEmpty {
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(3)
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
                    accentColor: impactColor(event.radioImpact)
                )
                .padding(.leading, 38) // align with text after icon
            }
        }
        .padding(.vertical, 2)
    }

    private func bannerColor(_ impact: RadioImpactLevel) -> Color {
        switch impact {
        case .extreme,
             .severe: .red
        case .moderate: .orange
        default: .yellow
        }
    }

    private func impactColor(_ impact: RadioImpactLevel) -> Color {
        switch impact {
        case .extreme: .red
        case .severe: .red
        case .moderate: .orange
        case .minor: .yellow
        case .none: .secondary
        }
    }

    private func impactLabel(_ impact: RadioImpactLevel) -> String {
        switch impact {
        case .extreme: "Extreme Storm"
        case .severe: "Storm Active"
        case .moderate: "Storm Active"
        default: "Space Weather"
        }
    }

    private func impactDetail(_ impact: RadioImpactLevel) -> String {
        switch impact {
        case .extreme: "HF severely degraded"
        case .severe: "HF degraded"
        case .moderate: "HF may be affected"
        default: "Monitoring activity"
        }
    }
}

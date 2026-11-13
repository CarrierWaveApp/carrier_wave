// Shared label content for activation rows (used in both normal and selection modes)

import CarrierWaveData
import SwiftUI

// MARK: - ActivationLabel

struct ActivationLabel: View {
    // MARK: Internal

    let activation: POTAActivation
    let metadata: ActivationMetadata?
    let showParkReference: Bool
    var isPartOfRove: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(activation.displayDate)
                    .font(.headline)
                    .lineLimit(1)
                    .layoutPriority(1)
                if showParkReference {
                    Text(activation.parkReference)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(activation.callsign)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if isPartOfRove {
                    roveBadge
                }
            }
            if let title = metadata?.title, !title.isEmpty {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            QSOTimelineView(qsos: activation.qsos, compact: true)

            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: activation.displayIconName)
                        .foregroundStyle(activation.displayColor)
                    Text(activation.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let watts = metadata?.watts {
                    Text("\(watts)W")
                        .font(.caption)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.purple.opacity(0.15))
                        .cornerRadius(4)
                }
                if let wpm = metadata?.averageWPM {
                    Text("\(wpm) WPM")
                        .font(.caption)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.15))
                        .cornerRadius(4)
                }
            }
            conditionsRow
        }
        .sheet(isPresented: $showingConditions) {
            if let meta = metadata {
                ActivationConditionsSheet(metadata: meta)
            }
        }
    }

    // MARK: Private

    @State private var showingConditions = false

    private var roveBadge: some View {
        Text("Rove")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.green)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.green.opacity(0.15))
            .clipShape(Capsule())
    }

    @ViewBuilder
    private var conditionsRow: some View {
        if let meta = metadata, meta.hasSolarData || meta.hasWeatherData {
            ConditionsGaugeRow(metadata: meta, showingSheet: $showingConditions)
        }
    }
}

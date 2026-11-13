import SwiftUI

// MARK: - TrailCalloutView

/// Detail callout shown when a trail is selected on the map.
struct TrailCalloutView: View {
    // MARK: Internal

    let trail: TrailBoundary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(trail.reference)
                    .font(.headline.monospaced())
                Spacer()
                if let matchQuality = trail.matchQuality {
                    Label(matchQuality, systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.brown)
                }
            }

            Text(trail.name)
                .font(.subheadline)
                .foregroundStyle(.primary)

            HStack(spacing: 16) {
                if let state = trail.state {
                    Label(state, systemImage: "mappin")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let miles = trail.lengthMiles {
                    Label(
                        formatLength(miles),
                        systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if let designation = trail.designation {
                    Text(designation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Color(.systemGray5),
                            in: RoundedRectangle(cornerRadius: 4)
                        )
                }
            }

            if let agency = trail.managingAgency {
                Label(agency, systemImage: "building.2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Private

    private func formatLength(_ miles: Double) -> String {
        if miles >= 100 {
            String(format: "%.0f mi", miles)
        } else if miles >= 10 {
            String(format: "%.1f mi", miles)
        } else {
            String(format: "%.1f mi", miles)
        }
    }
}

import SwiftUI

// MARK: - PropagationCheckSolarCard

/// Surfaces the space-weather snapshot captured when this propagation check
/// was started — K/A index, solar flux, sunspots, and the K-index-derived
/// propagation rating. Lives in its own file so it stays out of the results
/// view's body length budget.
struct PropagationCheckSolarCard: View {
    // MARK: Internal

    let check: PropagationCheck

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Space Weather", systemImage: "sun.max.fill")
                    .font(.headline)
                Spacer()
                if let rating = check.solarPropagationRating {
                    Text(rating)
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(ratingColor.opacity(0.18), in: Capsule())
                        .foregroundStyle(ratingColor)
                }
            }
            HStack(spacing: 16) {
                if let kIndex = check.solarKIndex {
                    tile("K-index", String(format: "%.1f", kIndex))
                }
                if let aIndex = check.solarAIndex {
                    tile("A-index", "\(aIndex)")
                }
                if let flux = check.solarFlux {
                    tile("SFI", "\(Int(flux))")
                }
                if let sunspots = check.solarSunspots {
                    tile("Sunspots", "\(sunspots)")
                }
            }
            if let timestamp = check.solarTimestamp {
                Text("Recorded \(timestamp, format: .dateTime.month().day().hour().minute())")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Private

    /// Matches `SolarConditions.propagationColor` so this badge reads the
    /// same here as it does in the live Solar panel.
    private var ratingColor: Color {
        switch check.solarKIndex ?? 0 {
        case 0 ..< 2: .green
        case 2 ..< 3: .blue
        case 3 ..< 4: .yellow
        case 4 ..< 5: .orange
        default: .red
        }
    }

    private func tile(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.bold().monospacedDigit())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

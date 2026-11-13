import SwiftUI

// MARK: - OnAirActiveFiltersView

/// Compact single-line summary of active On Air filters.
/// Shows "Filtered: 20m, 40m · CW, SSB · ≤30 min" style text.
struct OnAirActiveFiltersView: View {
    // MARK: Internal

    let bands: Set<String>
    let modes: Set<String>
    let maxAgeMinutes: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(summary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: Private

    private var summary: String {
        var parts: [String] = []
        if !bands.isEmpty {
            parts.append(sortedBands.joined(separator: ", "))
        }
        if !modes.isEmpty {
            parts.append(modes.sorted().joined(separator: ", "))
        }
        parts.append("≤\(maxAgeMinutes) min")
        return "Filtered: " + parts.joined(separator: " · ")
    }

    private var sortedBands: [String] {
        bands.sorted { lhs, rhs in
            let lhsNum = lhs.filter(\.isNumber)
            let rhsNum = rhs.filter(\.isNumber)
            return (Int(lhsNum) ?? 0) > (Int(rhsNum) ?? 0)
        }
    }
}

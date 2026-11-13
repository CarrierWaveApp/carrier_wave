// Worked Before Badges
//
// Shared badge view for displaying dupe/worked-before status
// on spot rows. Extracted from the identical implementations
// in POTASpotRow and SOTASpotRow.

import CarrierWaveData
import SwiftUI

// MARK: - WorkedBeforeBadges

/// Displays dupe, today-worked, or previous-worked badges for a spot
struct WorkedBeforeBadges: View {
    // MARK: Internal

    let band: String
    let mode: String
    let workedResult: WorkedBeforeResult

    var body: some View {
        let isDupe = workedResult.isDupe(on: band, mode: mode)
        if isDupe {
            dupeBadge
        } else if !workedResult.todayBands.isEmpty {
            todayWorkedBadge
        } else if !workedResult.previousBands.isEmpty {
            previousWorkedBadge
        }
    }

    // MARK: Private

    private var dupeBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
            Text("DUPE \(band) \(mode)")
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.orange.opacity(0.15))
        .clipShape(Capsule())
    }

    private var todayWorkedBadge: some View {
        HStack(spacing: 2) {
            Image(systemName: "checkmark")
                .font(.caption2)
            Text(workedResult.todayBands.sorted().joined(separator: " "))
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.orange.opacity(0.15))
        .clipShape(Capsule())
    }

    private var previousWorkedBadge: some View {
        HStack(spacing: 2) {
            Image(systemName: "checkmark")
                .font(.caption2)
            Text(workedResult.previousBands.sorted().joined(separator: " "))
                .font(.caption2.weight(.medium))
            Text("(prev)")
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
    }
}

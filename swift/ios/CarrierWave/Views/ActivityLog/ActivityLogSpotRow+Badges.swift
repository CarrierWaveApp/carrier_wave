import CarrierWaveData
import SwiftUI

// MARK: - Badge Helpers

extension ActivityLogSpotRow {
    var ageColumn: some View {
        HStack(spacing: 4) {
            Text(spot.spot.timeAgo)
                .font(.caption)
                .foregroundStyle(spot.spot.ageColor)
            Circle()
                .fill(spot.spot.ageColor)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Spotted \(spot.spot.timeAgo) ago")
    }

    var newDXCCBadge: some View {
        Text("\u{2605} NEW DXCC")
            .font(.caption2.weight(.bold))
            .foregroundStyle(Color(.systemBackground))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.blue)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .accessibilityLabel("New DXCC entity")
    }

    func statePill(_ state: String) -> some View {
        Text(state)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color(.tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .accessibilityLabel(USStates.fullName(for: state) ?? state)
    }

    func dupeBadge(band: String, mode: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
            Text("DUPE \(band) \(mode)")
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.orange)
        .badgePill(Color.orange.opacity(0.15))
    }

    func todayWorkedBadge(bands: Set<String>) -> some View {
        HStack(spacing: 2) {
            Image(systemName: "checkmark")
                .font(.caption2)
            Text(bands.sorted().joined(separator: " "))
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(.orange)
        .badgePill(Color.orange.opacity(0.15))
    }

    func previousWorkedBadge(bands: Set<String>) -> some View {
        HStack(spacing: 2) {
            Image(systemName: "checkmark")
                .font(.caption2)
            Text(bands.sorted().joined(separator: " "))
                .font(.caption2.weight(.medium))
            Text("(prev)")
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
    }
}

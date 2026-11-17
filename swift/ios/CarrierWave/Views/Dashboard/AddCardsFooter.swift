import CarrierWaveData
import SwiftUI

// MARK: - AddCardsFooter

/// Single muted row beneath the visible dashboard cards advertising the depth
/// available behind the Customize sheet. Replaces the previous "only the
/// slider icon in the toolbar tells you more exists" discoverability hole for
/// the lean default dashboard. Hidden once everything is visible.
struct AddCardsFooter: View {
    // MARK: Internal

    let hiddenSummary: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    if !hiddenSummary.isEmpty {
                        Text(hiddenSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        Color.secondary.opacity(0.25),
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show more dashboard cards")
        .accessibilityHint(
            hiddenSummary.isEmpty
                ? "Opens the customize dashboard sheet"
                : "Opens customize; hidden categories: \(hiddenSummary)"
        )
    }

    // MARK: Private

    private var headline: String {
        hiddenSummary.isEmpty ? "Show more cards" : "Show more here"
    }
}

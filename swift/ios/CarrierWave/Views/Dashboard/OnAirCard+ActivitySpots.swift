import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - Spot Summary for On Air Card

extension OnAirCard {
    /// Replaces the dashboard's POTA/SOTA/Friend spot sections for hunters,
    /// pointing them at the better Hunter Log spot list. Reuses the existing
    /// widget deep-link plumbing: `target: "hunt"` is consumed by
    /// `DeepLinkNotifications.handleWidgetDeepLink`, which switches the tab
    /// and posts `.didRequestHunterLog`.
    var openHunterLogLink: some View {
        Button {
            NotificationCenter.default.post(
                name: .didReceiveWidgetDeepLink,
                object: nil,
                userInfo: ["target": "hunt"]
            )
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "binoculars.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                Text("Open Hunter Log for live spots")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Hunter Log")
    }

    /// One-line spot count summary for non-hunters. The card is a glance
    /// surface — full spot rows (with club/contact badges and tap-to-spot)
    /// live on the On Air sheet, which the whole card opens on tap. Counts
    /// of zero are omitted; renders nothing when nothing is on the air.
    @ViewBuilder
    func spotsSummaryRow(potaCount: Int, sotaCount: Int, friendCount: Int) -> some View {
        let parts = spotsSummaryParts(
            potaCount: potaCount, sotaCount: sotaCount, friendCount: friendCount
        )
        if !parts.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text(parts.joined(separator: " · "))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "\(parts.joined(separator: ", ")). Tap for details."
            )
        }
    }

    private func spotsSummaryParts(
        potaCount: Int, sotaCount: Int, friendCount: Int
    ) -> [String] {
        var parts: [String] = []
        if friendCount > 0 {
            parts.append("\(friendCount) friend\(friendCount == 1 ? "" : "s") on air")
        }
        if potaCount > 0 {
            parts.append("\(potaCount) POTA")
        }
        if sotaCount > 0 {
            parts.append("\(sotaCount) SOTA")
        }
        return parts
    }
}

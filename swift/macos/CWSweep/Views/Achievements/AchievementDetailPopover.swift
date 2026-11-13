import CarrierWaveData
import SwiftUI

// MARK: - AchievementDetailPopover

/// macOS counterpart to the iOS AchievementDetailSheet. Anchored popover
/// with the badge icon, name, tier, description, and earned state.
struct AchievementDetailPopover: View {
    // MARK: Internal

    let achievement: Achievement
    let earned: Bool

    var body: some View {
        VStack(spacing: 12) {
            iconCircle
            VStack(spacing: 2) {
                Text(displayName)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                if let tier = achievement.tier, earned {
                    Text(tier.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(displayDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            statusPill
        }
        .padding(20)
        .frame(width: 260)
    }

    // MARK: Private

    private var locked: Bool {
        !earned && achievement.secret
    }

    private var displayName: String {
        locked ? "Locked Badge" : achievement.name
    }

    private var displayDescription: String {
        if locked {
            return "Earn this badge to reveal what it is."
        }
        return achievement.description
    }

    private var accentColor: Color {
        achievement.accentHex.flatMap(Color.init(hex:)) ?? .accentColor
    }

    private var iconCircle: some View {
        let symbol = locked ? "lock.fill" : achievement.iconName
        return Image(systemName: symbol)
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(earned ? accentColor : Color.secondary)
            .frame(width: 64, height: 64)
            .background(Circle().fill(accentColor.opacity(earned ? 0.18 : 0.08)))
    }

    @ViewBuilder
    private var statusPill: some View {
        if earned {
            Label("Earned", systemImage: "checkmark.seal.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(accentColor.opacity(0.15)))
        } else if !locked {
            Label("Not yet earned", systemImage: "circle.dashed")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.secondary.opacity(0.12)))
        }
    }
}

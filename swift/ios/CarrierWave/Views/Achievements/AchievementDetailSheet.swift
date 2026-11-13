import CarrierWaveData
import SwiftUI

// MARK: - AchievementDetailSheet

/// Detail sheet presented when the user taps a badge tile in the showcase.
/// Surfaces the description, tier, earned state, and award method.
struct AchievementDetailSheet: View {
    // MARK: Internal

    let achievement: Achievement
    let earned: Bool

    var body: some View {
        VStack(spacing: 16) {
            iconCircle
            VStack(spacing: 4) {
                Text(displayName)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                if let tier = achievement.tier, earned {
                    Text(tier.rawValue.capitalized)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Text(displayDescription)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            statusPill
            Spacer(minLength: 0)
        }
        .padding(.top, 32)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
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
            .font(.system(size: 36, weight: .semibold))
            .foregroundStyle(earned ? accentColor : Color.secondary)
            .frame(width: 88, height: 88)
            .background(Circle().fill(accentColor.opacity(earned ? 0.18 : 0.08)))
    }

    @ViewBuilder
    private var statusPill: some View {
        if earned {
            Label("Earned", systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accentColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(accentColor.opacity(0.15)))
        } else if !locked {
            Label("Not yet earned", systemImage: "circle.dashed")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.secondary.opacity(0.12)))
        }
    }
}

#Preview("Earned") {
    AchievementDetailSheet(
        achievement: .preview(id: "creator", name: "Creator", iconName: "hammer.fill"),
        earned: true
    )
}

#Preview("Locked") {
    AchievementDetailSheet(
        achievement: Achievement(
            id: "night-owl",
            name: "Night Owl",
            description: "Logged a contact between 0200 and 0400 local",
            category: .quirky,
            tier: nil,
            iconName: "moon.stars.fill",
            accentHex: "#5C6BC0",
            awardMethod: .auto,
            secret: true,
            sortOrder: 500
        ),
        earned: false
    )
}

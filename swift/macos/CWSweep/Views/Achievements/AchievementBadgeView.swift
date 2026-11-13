import CarrierWaveData
import SwiftUI

// MARK: - AchievementBadgeView

/// macOS counterpart to the iOS achievement tile. Mirrors the iOS look so
/// the user-facing badge surface feels the same on both platforms.
struct AchievementBadgeView: View {
    // MARK: Internal

    let achievement: Achievement
    let earned: Bool

    var body: some View {
        VStack(spacing: 6) {
            iconCircle
            Text(displayName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let tier = achievement.tier, earned {
                Text(tier.rawValue.capitalized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 96)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(earned ? 1.0 : 0.45)
        .help(achievement.description)
    }

    // MARK: Private

    private var displayName: String {
        if !earned, achievement.secret {
            return "Locked"
        }
        return achievement.name
    }

    private var accentColor: Color {
        achievement.accentHex.flatMap(Color.init(hex:)) ?? .accentColor
    }

    @ViewBuilder
    private var iconCircle: some View {
        let symbol = (!earned && achievement.secret) ? "lock.fill" : achievement.iconName
        Image(systemName: symbol)
            .font(.title2)
            .foregroundStyle(earned ? accentColor : Color.secondary)
            .frame(width: 44, height: 44)
            .background(Circle().fill(accentColor.opacity(earned ? 0.18 : 0.08)))
    }
}

// MARK: - Color hex helper

extension Color {
    init?(hex: String) {
        var trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#") {
            trimmed.removeFirst()
        }
        guard trimmed.count == 6, let value = UInt32(trimmed, radix: 16) else {
            return nil
        }
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}
